/// Order Book and Limit Order system for perpetual futures
module perp::perp_orderbook {
    use one::object::{UID, ID};
    use one::tx_context::TxContext;
    use one::balance::{Self, Balance};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::clock::{Self, Clock};
    use one::event;
    use one::table::{Self, Table};
    use std::string::String;
    use perp::perp_types;

    // ============================================
    // CONSTANTS
    // ============================================

    /// Maximum orders per user per pair
    const MAX_ORDERS_PER_USER: u64 = 50;
    /// Default order expiry (7 days in ms)
    const DEFAULT_EXPIRY_MS: u64 = 604800000;
    /// Minimum order size in USD
    const MIN_ORDER_SIZE_USD: u64 = 10_000_000_000; // $10

    // ============================================
    // STRUCTS
    // ============================================

    /// Limit order structure
    public struct LimitOrder has store, copy, drop {
        id: u64,
        trader: address,
        pair: String,
        is_long: bool,
        order_type: u8,        // ORDER_LIMIT, ORDER_STOP_LIMIT, etc.
        limit_price: u64,      // Price to execute at (1e10)
        trigger_price: u64,    // For stop orders, price that triggers
        size: u64,             // Position size in margin token
        leverage: u64,
        margin_mode: u8,       // ISOLATED or CROSS
        stop_loss: u64,
        take_profit: u64,
        broker_id: u32,
        created_at: u64,
        expires_at: u64,
        status: u8,
        filled_size: u64,
        reduce_only: bool,     // Only reduce existing position
        post_only: bool,       // Only maker orders
    }

    /// Price level in the order book
    public struct PriceLevel has store, drop {
        price: u64,
        total_size: u64,
        order_count: u64,
        orders: vector<u64>,   // Order IDs at this level
    }

    /// Order book for a single pair
    public struct PairOrderBook has store {
        /// Buy orders (bids) - sorted by price descending
        bids: vector<PriceLevel>,
        /// Sell orders (asks) - sorted by price ascending
        asks: vector<PriceLevel>,
        /// Best bid price
        best_bid: u64,
        /// Best ask price
        best_ask: u64,
        /// Total bid volume
        total_bid_volume: u64,
        /// Total ask volume
        total_ask_volume: u64,
    }

    /// Main order book manager
    public struct OrderBookManager has key {
        id: UID,
        admin: address,
        /// All orders by ID
        orders: Table<u64, LimitOrder>,
        /// User orders: user -> order_ids
        user_orders: Table<address, vector<u64>>,
        /// Pair order books
        pair_books: Table<String, PairOrderBook>,
        /// Locked margin for pending orders
        locked_margin: Balance<OCT>,
        /// Order ID counter
        next_order_id: u64,
        /// Is order book enabled
        enabled: bool,
        /// Minimum order size USD
        min_order_size_usd: u64,
        /// Maximum orders per user
        max_orders_per_user: u64,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct OrderBookCreated has copy, drop {
        manager_id: ID,
        admin: address,
    }

    public struct OrderPlaced has copy, drop {
        order_id: u64,
        trader: address,
        pair: String,
        is_long: bool,
        order_type: u8,
        limit_price: u64,
        size: u64,
        leverage: u64,
    }

    public struct OrderCancelled has copy, drop {
        order_id: u64,
        trader: address,
        reason: u8, // 0 = user, 1 = expired, 2 = insufficient margin
    }

    public struct OrderFilled has copy, drop {
        order_id: u64,
        trader: address,
        pair: String,
        is_long: bool,
        fill_price: u64,
        fill_size: u64,
        remaining_size: u64,
    }

    public struct OrderTriggered has copy, drop {
        order_id: u64,
        trigger_price: u64,
        market_price: u64,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let manager = OrderBookManager {
            id: object::new(ctx),
            admin,
            orders: table::new(ctx),
            user_orders: table::new(ctx),
            pair_books: table::new(ctx),
            locked_margin: balance::zero(),
            next_order_id: 1,
            enabled: true,
            min_order_size_usd: MIN_ORDER_SIZE_USD,
            max_orders_per_user: MAX_ORDERS_PER_USER,
        };

        event::emit(OrderBookCreated {
            manager_id: object::id(&manager),
            admin,
        });

        transfer::share_object(manager);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ============================================
    // ORDER PLACEMENT
    // ============================================

    /// Place a limit order
    public entry fun place_limit_order(
        manager: &mut OrderBookManager,
        pair: String,
        is_long: bool,
        limit_price: u64,
        margin: Coin<OCT>,
        leverage: u64,
        margin_mode: u8,
        stop_loss: u64,
        take_profit: u64,
        broker_id: u32,
        reduce_only: bool,
        post_only: bool,
        expiry_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(manager.enabled, perp_types::e_trading_disabled());
        assert!(limit_price > 0, perp_types::e_invalid_limit_price());

        let trader = tx_context::sender(ctx);
        let size = coin::value(&margin);
        let current_time = clock::timestamp_ms(clock);
        let expires_at = if (expiry_ms > 0) {
            current_time + expiry_ms
        } else {
            current_time + DEFAULT_EXPIRY_MS
        };

        // Check user order limit
        let user_order_count = get_user_order_count(manager, trader);
        assert!(user_order_count < manager.max_orders_per_user, perp_types::e_order_not_fillable());

        // Create order
        let order_id = manager.next_order_id;
        manager.next_order_id = order_id + 1;

        let order = LimitOrder {
            id: order_id,
            trader,
            pair,
            is_long,
            order_type: perp_types::order_limit(),
            limit_price,
            trigger_price: 0,
            size,
            leverage,
            margin_mode,
            stop_loss,
            take_profit,
            broker_id,
            created_at: current_time,
            expires_at,
            status: perp_types::order_status_open(),
            filled_size: 0,
            reduce_only,
            post_only,
        };

        // Lock margin
        balance::join(&mut manager.locked_margin, coin::into_balance(margin));

        // Store order
        table::add(&mut manager.orders, order_id, order);

        // Add to user orders
        if (!table::contains(&manager.user_orders, trader)) {
            table::add(&mut manager.user_orders, trader, vector::empty());
        };
        let user_orders = table::borrow_mut(&mut manager.user_orders, trader);
        vector::push_back(user_orders, order_id);

        // Add to order book
        add_to_orderbook(manager, pair, order_id, limit_price, size, is_long, ctx);

        event::emit(OrderPlaced {
            order_id,
            trader,
            pair,
            is_long,
            order_type: perp_types::order_limit(),
            limit_price,
            size,
            leverage,
        });
    }

    /// Place a stop-limit order
    public entry fun place_stop_limit_order(
        manager: &mut OrderBookManager,
        pair: String,
        is_long: bool,
        trigger_price: u64,
        limit_price: u64,
        margin: Coin<OCT>,
        leverage: u64,
        margin_mode: u8,
        stop_loss: u64,
        take_profit: u64,
        broker_id: u32,
        reduce_only: bool,
        expiry_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(manager.enabled, perp_types::e_trading_disabled());
        assert!(limit_price > 0, perp_types::e_invalid_limit_price());
        assert!(trigger_price > 0, perp_types::e_invalid_limit_price());

        let trader = tx_context::sender(ctx);
        let size = coin::value(&margin);
        let current_time = clock::timestamp_ms(clock);
        let expires_at = if (expiry_ms > 0) {
            current_time + expiry_ms
        } else {
            current_time + DEFAULT_EXPIRY_MS
        };

        let user_order_count = get_user_order_count(manager, trader);
        assert!(user_order_count < manager.max_orders_per_user, perp_types::e_order_not_fillable());

        let order_id = manager.next_order_id;
        manager.next_order_id = order_id + 1;

        let order = LimitOrder {
            id: order_id,
            trader,
            pair,
            is_long,
            order_type: perp_types::order_stop_limit(),
            limit_price,
            trigger_price,
            size,
            leverage,
            margin_mode,
            stop_loss,
            take_profit,
            broker_id,
            created_at: current_time,
            expires_at,
            status: perp_types::order_status_open(),
            filled_size: 0,
            reduce_only,
            post_only: false,
        };

        balance::join(&mut manager.locked_margin, coin::into_balance(margin));
        table::add(&mut manager.orders, order_id, order);

        if (!table::contains(&manager.user_orders, trader)) {
            table::add(&mut manager.user_orders, trader, vector::empty());
        };
        let user_orders = table::borrow_mut(&mut manager.user_orders, trader);
        vector::push_back(user_orders, order_id);

        // Stop orders are NOT added to visible order book until triggered

        event::emit(OrderPlaced {
            order_id,
            trader,
            pair,
            is_long,
            order_type: perp_types::order_stop_limit(),
            limit_price,
            size,
            leverage,
        });
    }

    // ============================================
    // ORDER CANCELLATION
    // ============================================

    /// Cancel an order
    public entry fun cancel_order(
        manager: &mut OrderBookManager,
        order_id: u64,
        ctx: &mut TxContext
    ) {
        assert!(table::contains(&manager.orders, order_id), perp_types::e_order_not_found());

        let order = table::borrow(&manager.orders, order_id);
        assert!(order.trader == tx_context::sender(ctx), perp_types::e_not_position_owner());
        assert!(order.status == perp_types::order_status_open(), perp_types::e_order_already_filled());

        let pair = order.pair;
        let is_long = order.is_long;
        let limit_price = order.limit_price;
        let remaining_size = order.size - order.filled_size;
        let trader = order.trader;

        // Remove from order book
        remove_from_orderbook(manager, pair, order_id, limit_price, remaining_size, is_long);

        // Update order status
        let order_mut = table::borrow_mut(&mut manager.orders, order_id);
        order_mut.status = perp_types::order_status_cancelled();

        // Return locked margin
        let refund = coin::from_balance(
            balance::split(&mut manager.locked_margin, remaining_size),
            ctx
        );
        transfer::public_transfer(refund, trader);

        event::emit(OrderCancelled {
            order_id,
            trader,
            reason: 0, // User cancelled
        });
    }

    /// Cancel all orders for a user
    public entry fun cancel_all_orders(
        manager: &mut OrderBookManager,
        ctx: &mut TxContext
    ) {
        let trader = tx_context::sender(ctx);

        if (!table::contains(&manager.user_orders, trader)) {
            return
        };

        let user_orders = table::borrow(&manager.user_orders, trader);
        let len = vector::length(user_orders);
        let mut i = 0;
        let mut to_cancel = vector::empty<u64>();

        while (i < len) {
            let order_id = *vector::borrow(user_orders, i);
            if (table::contains(&manager.orders, order_id)) {
                let order = table::borrow(&manager.orders, order_id);
                if (order.status == perp_types::order_status_open()) {
                    vector::push_back(&mut to_cancel, order_id);
                };
            };
            i = i + 1;
        };

        // Cancel each order
        let cancel_len = vector::length(&to_cancel);
        i = 0;
        while (i < cancel_len) {
            let order_id = *vector::borrow(&to_cancel, i);
            cancel_order_internal(manager, order_id, 0, ctx);
            i = i + 1;
        };
    }

    fun cancel_order_internal(
        manager: &mut OrderBookManager,
        order_id: u64,
        reason: u8,
        ctx: &mut TxContext
    ) {
        if (!table::contains(&manager.orders, order_id)) {
            return
        };

        let order = table::borrow(&manager.orders, order_id);
        if (order.status != perp_types::order_status_open()) {
            return
        };

        let pair = order.pair;
        let is_long = order.is_long;
        let limit_price = order.limit_price;
        let remaining_size = order.size - order.filled_size;
        let trader = order.trader;

        remove_from_orderbook(manager, pair, order_id, limit_price, remaining_size, is_long);

        let order_mut = table::borrow_mut(&mut manager.orders, order_id);
        order_mut.status = perp_types::order_status_cancelled();

        if (remaining_size > 0 && balance::value(&manager.locked_margin) >= remaining_size) {
            let refund = coin::from_balance(
                balance::split(&mut manager.locked_margin, remaining_size),
                ctx
            );
            transfer::public_transfer(refund, trader);
        };

        event::emit(OrderCancelled {
            order_id,
            trader,
            reason,
        });
    }

    // ============================================
    // ORDER MATCHING
    // ============================================

    /// Check if an order can be filled at current price
    public fun can_fill_order(
        manager: &OrderBookManager,
        order_id: u64,
        current_price: u64,
    ): bool {
        if (!table::contains(&manager.orders, order_id)) {
            return false
        };

        let order = table::borrow(&manager.orders, order_id);

        if (order.status != perp_types::order_status_open()) {
            return false
        };

        // Check trigger for stop orders
        if (order.order_type == perp_types::order_stop_limit() ||
            order.order_type == perp_types::order_stop_market()) {
            // Long stop: triggers when price >= trigger
            // Short stop: triggers when price <= trigger
            let triggered = if (order.is_long) {
                current_price >= order.trigger_price
            } else {
                current_price <= order.trigger_price
            };
            if (!triggered) {
                return false
            };
        };

        // Check limit price
        if (order.order_type == perp_types::order_limit() ||
            order.order_type == perp_types::order_stop_limit()) {
            // Long limit: fill when price <= limit
            // Short limit: fill when price >= limit
            if (order.is_long) {
                current_price <= order.limit_price
            } else {
                current_price >= order.limit_price
            }
        } else {
            // Market orders always fillable
            true
        }
    }

    /// Get order for filling (returns order details)
    public fun get_order_for_fill(
        manager: &OrderBookManager,
        order_id: u64,
    ): (bool, address, String, bool, u64, u64, u8, u64, u64, u32) {
        // exists, trader, pair, is_long, size, leverage, margin_mode, stop_loss, take_profit, broker_id
        if (!table::contains(&manager.orders, order_id)) {
            return (false, @0x0, std::string::utf8(b""), false, 0, 0, 0, 0, 0, 0)
        };

        let order = table::borrow(&manager.orders, order_id);
        let remaining = order.size - order.filled_size;

        (
            true,
            order.trader,
            order.pair,
            order.is_long,
            remaining,
            order.leverage,
            order.margin_mode,
            order.stop_loss,
            order.take_profit,
            order.broker_id
        )
    }

    /// Mark order as filled and release margin
    public fun mark_order_filled(
        manager: &mut OrderBookManager,
        order_id: u64,
        fill_size: u64,
        fill_price: u64,
        ctx: &mut TxContext
    ): Coin<OCT> {
        assert!(table::contains(&manager.orders, order_id), perp_types::e_order_not_found());

        let order = table::borrow_mut(&mut manager.orders, order_id);
        assert!(order.status == perp_types::order_status_open(), perp_types::e_order_already_filled());

        let remaining = order.size - order.filled_size;
        let actual_fill = if (fill_size > remaining) { remaining } else { fill_size };

        order.filled_size = order.filled_size + actual_fill;

        let new_remaining = order.size - order.filled_size;

        if (new_remaining == 0) {
            order.status = perp_types::order_status_filled();
        } else {
            order.status = perp_types::order_status_partially_filled();
        };

        let pair = order.pair;
        let trader = order.trader;
        let is_long = order.is_long;
        let limit_price = order.limit_price;

        // Remove filled size from order book
        remove_from_orderbook(manager, pair, order_id, limit_price, actual_fill, is_long);

        event::emit(OrderFilled {
            order_id,
            trader,
            pair,
            is_long,
            fill_price,
            fill_size: actual_fill,
            remaining_size: new_remaining,
        });

        // Return margin for the filled portion
        coin::from_balance(
            balance::split(&mut manager.locked_margin, actual_fill),
            ctx
        )
    }

    // ============================================
    // ORDER BOOK MANAGEMENT
    // ============================================

    fun add_to_orderbook(
        manager: &mut OrderBookManager,
        pair: String,
        order_id: u64,
        price: u64,
        size: u64,
        is_long: bool,
        ctx: &mut TxContext
    ) {
        // Ensure pair book exists
        if (!table::contains(&manager.pair_books, pair)) {
            table::add(&mut manager.pair_books, pair, PairOrderBook {
                bids: vector::empty(),
                asks: vector::empty(),
                best_bid: 0,
                best_ask: 0,
                total_bid_volume: 0,
                total_ask_volume: 0,
            });
        };

        let book = table::borrow_mut(&mut manager.pair_books, pair);

        if (is_long) {
            // Add to bids
            add_to_price_level(&mut book.bids, price, order_id, size, true);
            book.total_bid_volume = book.total_bid_volume + size;
            if (price > book.best_bid) {
                book.best_bid = price;
            };
        } else {
            // Add to asks
            add_to_price_level(&mut book.asks, price, order_id, size, false);
            book.total_ask_volume = book.total_ask_volume + size;
            if (book.best_ask == 0 || price < book.best_ask) {
                book.best_ask = price;
            };
        };
    }

    fun add_to_price_level(
        levels: &mut vector<PriceLevel>,
        price: u64,
        order_id: u64,
        size: u64,
        is_bid: bool, // true = descending order, false = ascending
    ) {
        let len = vector::length(levels);
        let mut found = false;
        let mut insert_idx = len;

        // Find existing level or insert position
        let mut i = 0;
        while (i < len) {
            let level = vector::borrow(levels, i);
            if (level.price == price) {
                found = true;
                insert_idx = i;
                break
            };
            if (is_bid && level.price < price) {
                insert_idx = i;
                break
            };
            if (!is_bid && level.price > price) {
                insert_idx = i;
                break
            };
            i = i + 1;
        };

        if (found) {
            let level = vector::borrow_mut(levels, insert_idx);
            level.total_size = level.total_size + size;
            level.order_count = level.order_count + 1;
            vector::push_back(&mut level.orders, order_id);
        } else {
            let mut orders = vector::empty();
            vector::push_back(&mut orders, order_id);
            let new_level = PriceLevel {
                price,
                total_size: size,
                order_count: 1,
                orders,
            };
            vector::insert(levels, new_level, insert_idx);
        };
    }

    fun remove_from_orderbook(
        manager: &mut OrderBookManager,
        pair: String,
        order_id: u64,
        price: u64,
        size: u64,
        is_long: bool,
    ) {
        if (!table::contains(&manager.pair_books, pair)) {
            return
        };

        let book = table::borrow_mut(&mut manager.pair_books, pair);

        let levels = if (is_long) {
            &mut book.bids
        } else {
            &mut book.asks
        };

        let len = vector::length(levels);
        let mut level_idx = len;

        // Find the price level
        let mut i = 0;
        while (i < len) {
            if (vector::borrow(levels, i).price == price) {
                level_idx = i;
                break
            };
            i = i + 1;
        };

        if (level_idx >= len) {
            return
        };

        let level = vector::borrow_mut(levels, level_idx);

        // Remove order from level
        let order_len = vector::length(&level.orders);
        let mut j = 0;
        while (j < order_len) {
            if (*vector::borrow(&level.orders, j) == order_id) {
                vector::remove(&mut level.orders, j);
                level.order_count = level.order_count - 1;
                level.total_size = if (level.total_size >= size) {
                    level.total_size - size
                } else { 0 };
                break
            };
            j = j + 1;
        };

        // Update totals
        if (is_long) {
            book.total_bid_volume = if (book.total_bid_volume >= size) {
                book.total_bid_volume - size
            } else { 0 };
        } else {
            book.total_ask_volume = if (book.total_ask_volume >= size) {
                book.total_ask_volume - size
            } else { 0 };
        };

        // Remove empty levels and update best prices
        if (level.order_count == 0) {
            vector::remove(levels, level_idx);
            update_best_prices(book, is_long);
        };
    }

    fun update_best_prices(book: &mut PairOrderBook, was_bid: bool) {
        if (was_bid) {
            if (vector::length(&book.bids) > 0) {
                book.best_bid = vector::borrow(&book.bids, 0).price;
            } else {
                book.best_bid = 0;
            };
        } else {
            if (vector::length(&book.asks) > 0) {
                book.best_ask = vector::borrow(&book.asks, 0).price;
            } else {
                book.best_ask = 0;
            };
        };
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    public entry fun set_enabled(
        manager: &mut OrderBookManager,
        enabled: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.enabled = enabled;
    }

    public entry fun set_min_order_size(
        manager: &mut OrderBookManager,
        min_size_usd: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.min_order_size_usd = min_size_usd;
    }

    public entry fun set_max_orders_per_user(
        manager: &mut OrderBookManager,
        max_orders: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.max_orders_per_user = max_orders;
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    public fun get_best_bid(manager: &OrderBookManager, pair: String): u64 {
        if (!table::contains(&manager.pair_books, pair)) {
            return 0
        };
        table::borrow(&manager.pair_books, pair).best_bid
    }

    public fun get_best_ask(manager: &OrderBookManager, pair: String): u64 {
        if (!table::contains(&manager.pair_books, pair)) {
            return 0
        };
        table::borrow(&manager.pair_books, pair).best_ask
    }

    public fun get_spread(manager: &OrderBookManager, pair: String): u64 {
        let best_bid = get_best_bid(manager, pair);
        let best_ask = get_best_ask(manager, pair);
        if (best_bid == 0 || best_ask == 0) {
            return 0
        };
        if (best_ask > best_bid) {
            best_ask - best_bid
        } else {
            0
        }
    }

    public fun get_mid_price(manager: &OrderBookManager, pair: String): u64 {
        let best_bid = get_best_bid(manager, pair);
        let best_ask = get_best_ask(manager, pair);
        if (best_bid == 0 || best_ask == 0) {
            return 0
        };
        (best_bid + best_ask) / 2
    }

    public fun get_total_bid_volume(manager: &OrderBookManager, pair: String): u64 {
        if (!table::contains(&manager.pair_books, pair)) {
            return 0
        };
        table::borrow(&manager.pair_books, pair).total_bid_volume
    }

    public fun get_total_ask_volume(manager: &OrderBookManager, pair: String): u64 {
        if (!table::contains(&manager.pair_books, pair)) {
            return 0
        };
        table::borrow(&manager.pair_books, pair).total_ask_volume
    }

    public fun get_user_order_count(manager: &OrderBookManager, user: address): u64 {
        if (!table::contains(&manager.user_orders, user)) {
            return 0
        };

        let orders = table::borrow(&manager.user_orders, user);
        let len = vector::length(orders);
        let mut count = 0;
        let mut i = 0;

        while (i < len) {
            let order_id = *vector::borrow(orders, i);
            if (table::contains(&manager.orders, order_id)) {
                let order = table::borrow(&manager.orders, order_id);
                if (order.status == perp_types::order_status_open() ||
                    order.status == perp_types::order_status_partially_filled()) {
                    count = count + 1;
                };
            };
            i = i + 1;
        };

        count
    }

    public fun get_order(manager: &OrderBookManager, order_id: u64): (bool, LimitOrder) {
        if (!table::contains(&manager.orders, order_id)) {
            return (false, LimitOrder {
                id: 0,
                trader: @0x0,
                pair: std::string::utf8(b""),
                is_long: false,
                order_type: 0,
                limit_price: 0,
                trigger_price: 0,
                size: 0,
                leverage: 0,
                margin_mode: 0,
                stop_loss: 0,
                take_profit: 0,
                broker_id: 0,
                created_at: 0,
                expires_at: 0,
                status: 0,
                filled_size: 0,
                reduce_only: false,
                post_only: false,
            })
        };

        (true, *table::borrow(&manager.orders, order_id))
    }

    public fun is_enabled(manager: &OrderBookManager): bool {
        manager.enabled
    }

    public fun total_locked_margin(manager: &OrderBookManager): u64 {
        balance::value(&manager.locked_margin)
    }
}
