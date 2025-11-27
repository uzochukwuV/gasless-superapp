module core_contracts::product_catalog {
    use one::object;
    use one::object::{UID, ID};
    use one::tx_context::TxContext;
    use one::transfer;
    use one::coin;
    use one::coin::Coin;
    use one::oct::OCT;
    use one::event;
    use one::table;
    use one::table::Table;
    use one::clock;
    use one::clock::Clock;
    use std::string::String;
    use std::vector;
    use core_contracts::receipt_nft::{ReceiptNFT, mint};

    //
    // Small helper struct instead of tuple<(u64,u64)> (tuples are not supported as vector element types)
    //
    public struct BulkDiscount has store, drop {
        min_quantity: u64,
        percent_off: u64, // 0..100
    }

    /// A single purchase record stored per-buyer as a vector
    public struct PurchaseRecord has store, drop {
        quantity: u64,
        total_paid: u64,
        timestamp: u64,
        receipt_nft_id: ID,
    }

    /// Product listing created by merchant
    public struct Product has key, store {
        id: UID,
        merchant: address,
        name: String,
        description: String,
        price: u64,              // price per unit in MIST (1 OCT = 1e9 MIST)
        max_supply: u64,
        sold_count: u64,
        active: bool,
        created_at: u64,
        buyers: Table<address, vector<PurchaseRecord>>, // each buyer -> list of purchases
        bulk_discounts: vector<BulkDiscount>,
        category: String,
        refunds: Table<address, u64>, // buyer -> total refund requested (in MIST)
    }

    /// Merchant store that contains products
    public struct MerchantStore has key {
        id: UID,
        owner: address,
        name: String,
        product_ids: vector<ID>,
        total_revenue: u64,
    }

    // Events
    public struct ProductCreated has copy, drop {
        product_id: ID,
        merchant: address,
        name: String,
        price: u64,
        max_supply: u64,
        category: String,
    }

    public struct ProductPurchased has copy, drop {
        product_id: ID,
        buyer: address,
        quantity: u64,
        total_paid: u64,
        receipt_id: ID,
    }

    public struct RefundRequested has copy, drop {
        product_id: ID,
        buyer: address,
        amount: u64,
    }

    public struct RefundFulfilled has copy, drop {
        product_id: ID,
        buyer: address,
        amount: u64,
    }

    // Errors
    const EInsufficientPayment: u64 = 0;
    const EProductSoldOut: u64 = 1;
    const EProductInactive: u64 = 2;
    const ENotMerchant: u64 = 3;
    const ENoRefundRequested: u64 = 4;
    const ERefundPaymentTooSmall: u64 = 5;

    // ---------------------
    // Create product
    // ---------------------
    public entry fun create_product(
        store: &mut MerchantStore,
        name: String,
        description: String,
        price: u64,
        max_supply: u64,
        category: String,
        min_quantities: vector<u64>,
        percent_discounts: vector<u64>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(store.owner == ctx.sender(), ENotMerchant);

        let mut discounts = vector::empty<BulkDiscount>();
        let len = vector::length(&min_quantities);
        let mut i = 0;
        while (i < len) {
            let min_q = *vector::borrow(&min_quantities, i);
            let pct = *vector::borrow(&percent_discounts, i);

            vector::push_back(&mut discounts, BulkDiscount {
                min_quantity: min_q,
                percent_off: pct
            });

            i = i + 1;
        };

        let product = Product {
            id: object::new(ctx),
            merchant: ctx.sender(),
            name,
            description,
            price,
            max_supply,
            sold_count: 0,
            active: true,
            created_at: clock::timestamp_ms(clock),
            buyers: table::new(ctx),
            bulk_discounts: discounts,
            category,
            refunds: table::new(ctx),
        };

        let product_id = object::id(&product);
        vector::push_back(&mut store.product_ids, product_id);

        event::emit(ProductCreated {
            product_id,
            merchant: ctx.sender(),
            name: product.name,
            price,
            max_supply,
            category: product.category,
        });

        // Make product shareable so customers can hold references to it
        transfer::share_object(product);
    }

    // ---------------------
    // Purchase product
    // ---------------------
    // Returns (change_coin, receipt)
    public fun purchase_product(
        product: &mut Product,
        mut payment: Coin<OCT>,
        quantity: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<OCT>, ReceiptNFT) {
        assert!(product.active, EProductInactive);
        assert!(product.sold_count + quantity <= product.max_supply, EProductSoldOut);

        // base cost
        let mut total_cost = product.price * quantity;

        // compute best bulk discount (largest percent_off where min_quantity <= quantity)
        let mut best_discount:u64 = 0;
        let bd_len = vector::length(&product.bulk_discounts);
        let mut i = 0;
        while (i < bd_len) {
            let bd_ref = vector::borrow(&product.bulk_discounts, i);
            if (quantity >= bd_ref.min_quantity && bd_ref.percent_off > best_discount) {
                best_discount = bd_ref.percent_off;
            };
            i = i + 1;
        };

        // Apply discount
        if (best_discount > 0) {
            total_cost = total_cost * (100 - best_discount) / 100;
        };

        // Ensure payer sent enough
        assert!(coin::value(&payment) >= total_cost, EInsufficientPayment);

        let buyer = ctx.sender();

        // Split merchant portion
        let merchant_payment = coin::split(&mut payment, total_cost, ctx);

        // Mint receipt NFT
        let receipt = mint(
            product.name,
            product.merchant,
            buyer,
            quantity,
            total_cost,
            clock::timestamp_ms(clock),
            ctx
        );
        let receipt_id = object::id(&receipt);

        // Ensure buyer has vector of purchases
        if (!table::contains(&product.buyers, buyer)) {
            table::add(&mut product.buyers, buyer, vector::empty<PurchaseRecord>());
        };

        // Append purchase record
        let purchases_ref = table::borrow_mut(&mut product.buyers, buyer);
        vector::push_back(purchases_ref, PurchaseRecord {
            quantity,
            total_paid: total_cost,
            timestamp: clock::timestamp_ms(clock),
            receipt_nft_id: receipt_id,
        });

        // Update sold count and revenue (store.total_revenue not accessible here; merchant collects via coins)
        product.sold_count = product.sold_count + quantity;

        // Transfer merchant payment (merchant receives the coin)
        transfer::public_transfer(merchant_payment, product.merchant);

        event::emit(ProductPurchased {
            product_id: object::id(product),
            buyer,
            quantity,
            total_paid: total_cost,
            receipt_id,
        });

        // Return change coin and receipt
        (payment, receipt)
    }

    // ---------------------
    // Buyer requests refund for ALL their purchases on this product.
    // This stores a refund request amount in `product.refunds`.
    // Merchant later calls `fulfill_refund` and provides actual funds (Coin<OCT>).
    // ---------------------
    public entry fun request_refund(
        product: &mut Product,
        ctx: &mut TxContext
    ) {
        let buyer = ctx.sender();

        // if no purchases, nothing to request
        assert!(table::contains(&product.buyers, buyer), ENoRefundRequested);

        // sum up buyer purchases
       let purchases = table::borrow(&product.buyers, buyer);

        let mut total_refund = 0u64;
        let mut sold_total = 0u64;
        let len = vector::length(purchases);

        let mut i = 0;
        while (i < len) {
            let p = vector::borrow(purchases, i);
            total_refund = total_refund + p.total_paid;
            sold_total = sold_total + p.quantity;
            i = i + 1;
        };

        // Drop the borrow
        // Now safe to remove
        let _ = table::remove(&mut product.buyers, buyer);

        product.sold_count = product.sold_count - sold_total;

        // store refund request amount in refunds table (accumulate if already exists)
        if (table::contains(&product.refunds, buyer)) {
            let prev = *table::borrow(&product.refunds, buyer);
            let new_total = prev + total_refund;
            table::remove(&mut product.refunds, buyer);
            table::add(&mut product.refunds, buyer, new_total);
        } else {
            table::add(&mut product.refunds, buyer, total_refund);
        };

        event::emit(RefundRequested {
            product_id: object::id(product),
            buyer,
            amount: total_refund,
        });
    }

    // ---------------------
    // Merchant fulfills refund by providing actual Coin<OCT> funds.
    // This function takes a mutable payment coin (from merchant) and splits/forwards refund to buyer.
    // ---------------------
    public entry fun fulfill_refund(
        product: &mut Product,
        buyer: address,
        mut refund_payment: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        assert!(product.merchant == ctx.sender(), ENotMerchant);
        assert!(table::contains(&product.refunds, buyer), ENoRefundRequested);

        let amount = *table::borrow(&product.refunds, buyer);

        // require merchant provided enough in refund_payment
        assert!(coin::value(&refund_payment) >= amount, ERefundPaymentTooSmall);

        let to_send = coin::split(&mut refund_payment, amount, ctx);
        transfer::public_transfer(to_send, buyer);
        transfer::public_transfer(refund_payment, ctx.sender());
        // cleanup refunds table entry
        table::remove(&mut product.refunds, buyer);

        event::emit(RefundFulfilled {
            product_id: object::id(product),
            buyer,
            amount,
        });
    }

     public entry fun create_merchant_store(
        name: String,
        ctx: &mut TxContext
    ) {
        let store = MerchantStore {
            id: object::new(ctx),
            owner: ctx.sender(),
            name,
            product_ids: vector::empty<ID>(),
            total_revenue: 0,
        };

        transfer::share_object(store);
    }

    // Merchant can deactivate product
    public entry fun deactivate_product(
        product: &mut Product,
        ctx: &mut TxContext
    ) {
        assert!(product.merchant == ctx.sender(), ENotMerchant);
        product.active = false;
    }

    // Read-only helpers
    public fun get_purchase_records(
        product: &Product,
        buyer: address
    ): &vector<PurchaseRecord> {
        table::borrow(&product.buyers, buyer)
    }

    public fun get_product_info(product: &Product): (String, String, u64, u64, u64, bool, String) {
        (
            product.name,
            product.description,
            product.price,
            product.max_supply,
            product.sold_count,
            product.active,
            product.category
        )
    }
}
