module core_contracts::p2p_orderbook {
    use one::object;
    use one::object::{UID, ID};
    use one::tx_context::TxContext;
    use one::transfer;
    use one::coin;
    use one::coin::Coin;
    use one::event;
    use one::clock;
    use std::string::String;
    use std::vector;

    //
    // Simple on-chain P2P orderbook for a single pair (Base / Quote).
    // - Orders escrow coins inside order objects.
    // - Order objects are created & shared with the owner (so they keep a handle).
    // - Matching is performed by passing both order objects into the matching entry.
    //

    public struct OrderBook<phantom Base, phantom Quote> has key {
        id: UID,
        creator: address,
        name: String,
        bids: vector<ID>, // IDs of BidOrder<Base,Quote>
        asks: vector<ID>, // IDs of AskOrder<Base,Quote>
    }

    public struct BidOrder<phantom Base, phantom Quote> has key, store {
        id: UID,
        owner: address,
        price: u64, // quote units per 1 base unit
        quantity_base_remaining: u64,
        escrow_quote: Coin<Quote>,
        created_at_ms: u64,
    }

    public struct AskOrder<phantom Base, phantom Quote> has key, store {
        id: UID,
        owner: address,
        price: u64,
        quantity_base_remaining: u64,
        escrow_base: Coin<Base>,
        created_at_ms: u64,
    }

    // Events
    public struct BidPlaced has copy, drop {
        book_id: ID,
        order_id: ID,
        owner: address,
        price: u64,
        quantity: u64,
    }

    public struct AskPlaced has copy, drop {
        book_id: ID,
        order_id: ID,
        owner: address,
        price: u64,
        quantity: u64,
    }

    public struct OrdersMatched has copy, drop {
        book_id: ID,
        bid_id: ID,
        ask_id: ID,
        quantity: u64,
        price: u64,
    }

    public struct OrderCancelled has copy, drop {
        book_id: ID,
        order_id: ID,
        owner: address,
    }

    // -----------------------
    // Create orderbook (creates object and shares it with creator)
    // -----------------------
    public entry fun create_orderbook<Base, Quote>(
        name: String,
        ctx: &mut TxContext
    ) {
        let book: OrderBook<Base, Quote> = OrderBook {
            id: object::new(ctx),
            creator: ctx.sender(),
            name,
            bids: vector::empty<ID>(),
            asks: vector::empty<ID>(),
        };

        // Share the orderbook with its creator so they keep a handle
        transfer::share_object(book);
    }

    // -----------------------
    // Place a bid: escrow Quote coins and create a BidOrder shared to owner
    // Caller passes payment_quote containing at least price * quantity_base
    // -----------------------
    public entry fun place_bid<Base, Quote>(
        mut book: OrderBook<Base, Quote>,
        mut payment_quote: Coin<Quote>,
        quantity_base: u64,
        price: u64,
        clock: &clock::Clock,
        ctx: &mut TxContext
    ) {
        // required quote = price * quantity_base (use u128 for intermediate safety)
        let required_128: u128 = (price as u128) * (quantity_base as u128);
        // Guard: ensure required fits u64 (practical guard)
        assert!(required_128 <= 18446744073709551615u128, 1000);
        let required: u64 = required_128 as u64;

        // ensure payment is sufficient
        assert!(coin::value(&payment_quote) >= required, 1001);

        // split escrow portion from payment_quote (this moves coins into escrow)
        let escrow = coin::split(&mut payment_quote, required, ctx);

        // return leftover change (if any) to sender
        if (coin::value(&payment_quote) > 0) {
            transfer::public_transfer(payment_quote, ctx.sender());
        };

        // create bid order and share to owner
        let bid : BidOrder<Base, Quote> = BidOrder {
            id: object::new(ctx),
            owner: ctx.sender(),
            price,
            quantity_base_remaining: quantity_base,
            escrow_quote: escrow,
            created_at_ms: clock::timestamp_ms(clock),
        };

        let bid_id = object::id(&bid);
        vector::push_back(&mut book.bids, bid_id);

        // share order object so owner keeps a handle
        transfer::share_object(bid);

        event::emit(BidPlaced {
            book_id: object::id(&book),
            order_id: bid_id,
            owner: ctx.sender(),
            price,
            quantity: quantity_base,
        });
    }

    // -----------------------
    // Place an ask: escrow Base coins and create an AskOrder shared to owner
    // Caller passes payment_base containing at least quantity_base base tokens
    // -----------------------
    public entry fun place_ask<Base, Quote>(
        mut book: OrderBook<Base, Quote>,
        mut payment_base: Coin<Base>,
        quantity_base: u64,
        price: u64,
        clock: &clock::Clock,
        ctx: &mut TxContext
    ) {
        // ensure provided base is sufficient
        assert!(coin::value(&payment_base) >= quantity_base, 1002);

        // split escrow_base from provided base coin
        let escrow = coin::split(&mut payment_base, quantity_base, ctx);

        // return leftover base to sender
        if (coin::value(&payment_base) > 0) {
            transfer::public_transfer(payment_base, ctx.sender());
        };

        let ask: AskOrder<Base, Quote> = AskOrder {
            id: object::new(ctx),
            owner: ctx.sender(),
            price,
            quantity_base_remaining: quantity_base,
            escrow_base: escrow,
            created_at_ms: clock::timestamp_ms(clock),
        };

        let ask_id = object::id(&ask);
        vector::push_back(&mut book.asks, ask_id);

        transfer::share_object(ask);

        event::emit(AskPlaced {
            book_id: object::id(&book),
            order_id: ask_id,
            owner: ctx.sender(),
            price,
            quantity: quantity_base,
        });
    }

    // -----------------------
    // Cancel bid: owner calls and passes the bid order object in.
    // Return leftover escrow and remove id from book.
    // -----------------------
    public entry fun cancel_bid<Base, Quote>(
        mut book: OrderBook<Base, Quote>,
        mut bid: BidOrder<Base, Quote>,
        ctx: &mut TxContext
    ) {
        assert!(bid.owner == ctx.sender(), 1003);

        // move escrow coin out and send back
        let escrow_to_return: Coin<Quote> = bid.escrow_quote; 
        transfer::public_transfer(escrow_to_return, bid.owner);

        // Rebuild book.bids excluding this id
        let bid_id = object::id(&bid);
        let new_bids = remove_id_and_rebuild(&mut book.bids, bid_id);
        book.bids = new_bids;

        // return the (now-empty) bid object to owner so they keep handle
        transfer::public_transfer(bid, bid.owner);

        event::emit(OrderCancelled {
            book_id: object::id(&book),
            order_id: bid_id,
            owner: ctx.sender(),
        });
    }

    // -----------------------
    // Cancel ask: owner passes ask object; return escrow and remove id from book
    // -----------------------
    public entry fun cancel_ask<Base, Quote>(
        mut book: OrderBook<Base, Quote>,
        mut ask: AskOrder<Base, Quote>,
        ctx: &mut TxContext
    ) {
        assert!(ask.owner == ctx.sender(), 1004);

        let escrow_to_return: Coin<Base> = ask.escrow_base;
        transfer::public_transfer(escrow_to_return, ask.owner);

        let ask_id = object::id(&ask);
        let new_asks = remove_id_and_rebuild(&mut book.asks, ask_id);
        book.asks = new_asks;

        transfer::public_transfer(ask, ask.owner);

        event::emit(OrderCancelled {
            book_id: object::id(&book),
            order_id: ask_id,
            owner: ctx.sender(),
        });
    }

    // -----------------------
    // Match a bid and an ask. Any caller can call this by providing the order objects.
    // Both bid and ask objects are moved into this function (ownership).
    // After settlement, the order objects are either returned (shared) to owners if partially filled,
    // or transferred back (final) if fully filled.
    // -----------------------
    public entry fun match_orders<Base, Quote>(
        mut book: OrderBook<Base, Quote>,
        mut bid: BidOrder<Base, Quote>,
        mut ask: AskOrder<Base, Quote>,
        ctx: &mut TxContext
    ) {
        // Price crossing must hold
        assert!(bid.price >= ask.price, 1005);

        // matched quantity = min(bid_remaining, ask_remaining)
        let matched: u64;
        if bid.quantity_base_remaining <= ask.quantity_base_remaining {
            matched = bid.quantity_base_remaining;
        } else {
            matched = ask.quantity_base_remaining;
        }

        assert!(matched > 0, 1006);

        // compute quote needed = ask.price * matched (u128 intermediate)
        let quote_needed_128: u128 = (ask.price as u128) * (matched as u128);
        assert!(quote_needed_128 <= 18446744073709551615u128, 1007);
        let quote_needed: u64 = quote_needed_128 as u64;

        // transfer base from ask.escrow_base -> bid.owner
        let base_to_send = coin::split(&mut ask.escrow_base, matched, ctx);
        transfer::public_transfer(base_to_send, bid.owner);

        // transfer quote from bid.escrow_quote -> ask.owner
        let quote_to_send = coin::split(&mut bid.escrow_quote, quote_needed, ctx);
        transfer::public_transfer(quote_to_send, ask.owner);

        // update remaining quantities
        bid.quantity_base_remaining = bid.quantity_base_remaining - matched;
        ask.quantity_base_remaining = ask.quantity_base_remaining - matched;

        let bid_id = object::id(&bid);
        let ask_id = object::id(&ask);

        // If bid fully filled, remove from book.bids and return remaining escrow (if any) then transfer order back
        if (bid.quantity_base_remaining == 0) {
            let new_bids = remove_id_and_rebuild(&mut book.bids, bid_id);
            book.bids = new_bids;

            // move leftover escrow (if any) and return to owner
            if (coin::value(&bid.escrow_quote) > 0) {
                let leftover = bid.escrow_quote;
                transfer::public_transfer(leftover, bid.owner);
            };

            // transfer order object back to owner (now empty)
            transfer::public_transfer(bid, bid.owner);
        } else {
            // partially filled: share order back with owner
            transfer::share_object(bid);
        };

        // If ask fully filled, remove from book.asks and return leftover base then transfer order back
        if (ask.quantity_base_remaining == 0) {
            let new_asks = remove_id_and_rebuild(&mut book.asks, ask_id);
            book.asks = new_asks;

            if (coin::value(&ask.escrow_base) > 0) {
                let leftover_b = ask.escrow_base;
                transfer::public_transfer(leftover_b, ask.owner);
            };

            transfer::public_transfer(ask, ask.owner);
        } else {
            transfer::share_object(ask);
        };

        event::emit(OrdersMatched {
            book_id: object::id(&book),
            bid_id,
            ask_id,
            quantity: matched,
            price: ask.price,
        });
    }

    // -----------------------
    // Helper: rebuild a vector<ID> excluding a specific ID (safe Move pattern)
    // -----------------------
    fun remove_id_and_rebuild(vec: &mut vector<ID>, id_to_remove: ID): vector<ID> {
        let len = vector::length(vec);
        let mut i = 0;
        let mut new_vec = vector::empty<ID>();
        while (i < len) {
            let cur = *vector::borrow(vec, i);
            if (!(cur == id_to_remove)) {
                vector::push_back(&mut new_vec, cur);
            };
            i = i + 1;
        };
        new_vec
    }
}
