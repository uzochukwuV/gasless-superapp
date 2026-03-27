/// Price oracle module for the perpetual exchange
module perp::perp_oracle {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::table::{Self, Table};
    use one::clock::{Self, Clock};
    use one::event;
    use std::string::{Self, String};
    use perp::perp_types;

    // ============================================
    // CONSTANTS
    // ============================================

    const DEFAULT_MAX_AGE_MS: u64 = 60000; // 1 minute staleness
    const MAX_PRICE_DEVIATION_BPS: u64 = 1000; // 10% max deviation

    // ============================================
    // STRUCTS
    // ============================================

    /// Price data for a token
    public struct PriceData has store, copy, drop {
        price: u64,             // Price in USD (1e10 precision)
        timestamp: u64,         // Last update timestamp (ms)
        confidence: u64,        // Confidence interval
    }

    /// Price oracle
    public struct Oracle has key {
        id: UID,
        admin: address,
        updaters: Table<address, bool>,
        prices: Table<String, PriceData>,
        max_age_ms: u64,
        max_deviation_bps: u64,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct OracleCreated has copy, drop {
        oracle_id: ID,
        admin: address,
    }

    public struct PriceUpdated has copy, drop {
        token: String,
        price: u64,
        timestamp: u64,
    }

    public struct UpdaterAdded has copy, drop {
        updater: address,
    }

    public struct UpdaterRemoved has copy, drop {
        updater: address,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let mut oracle = Oracle {
            id: object::new(ctx),
            admin,
            updaters: table::new(ctx),
            prices: table::new(ctx),
            max_age_ms: DEFAULT_MAX_AGE_MS,
            max_deviation_bps: MAX_PRICE_DEVIATION_BPS,
        };

        // Admin is default updater
        table::add(&mut oracle.updaters, admin, true);

        event::emit(OracleCreated {
            oracle_id: object::id(&oracle),
            admin,
        });

        transfer::share_object(oracle);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    public entry fun add_updater(
        oracle: &mut Oracle,
        updater: address,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == oracle.admin, perp_types::e_not_admin());

        if (!table::contains(&oracle.updaters, updater)) {
            table::add(&mut oracle.updaters, updater, true);
        };

        event::emit(UpdaterAdded { updater });
    }

    public entry fun remove_updater(
        oracle: &mut Oracle,
        updater: address,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == oracle.admin, perp_types::e_not_admin());

        if (table::contains(&oracle.updaters, updater)) {
            table::remove(&mut oracle.updaters, updater);
        };

        event::emit(UpdaterRemoved { updater });
    }

    public entry fun set_max_age(
        oracle: &mut Oracle,
        max_age_ms: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == oracle.admin, perp_types::e_not_admin());
        oracle.max_age_ms = max_age_ms;
    }

    public entry fun set_max_deviation(
        oracle: &mut Oracle,
        max_deviation_bps: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == oracle.admin, perp_types::e_not_admin());
        oracle.max_deviation_bps = max_deviation_bps;
    }

    // ============================================
    // PRICE UPDATE FUNCTIONS
    // ============================================

    /// Update price for a single token
    public entry fun update_price(
        oracle: &mut Oracle,
        token: String,
        price: u64,
        confidence: u64,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&oracle.updaters, sender), perp_types::e_not_admin());
        assert!(price > 0, perp_types::e_invalid_price());

        let timestamp = clock::timestamp_ms(clock);

        // Check deviation if price exists
        if (table::contains(&oracle.prices, token)) {
            let old_data = table::borrow(&oracle.prices, token);
            let deviation = calculate_deviation(old_data.price, price);
            assert!(deviation <= oracle.max_deviation_bps, perp_types::e_price_deviation_too_high());
            table::remove(&mut oracle.prices, token);
        };

        table::add(&mut oracle.prices, token, PriceData {
            price,
            timestamp,
            confidence,
        });

        event::emit(PriceUpdated { token, price, timestamp });
    }

    /// Batch update prices
    public entry fun update_prices_batch(
        oracle: &mut Oracle,
        tokens: vector<String>,
        prices: vector<u64>,
        confidences: vector<u64>,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&oracle.updaters, sender), perp_types::e_not_admin());

        let len = vector::length(&tokens);
        assert!(len == vector::length(&prices), perp_types::e_invalid_price());
        assert!(len == vector::length(&confidences), perp_types::e_invalid_price());

        let timestamp = clock::timestamp_ms(clock);
        let mut i = 0;

        while (i < len) {
            let token = *vector::borrow(&tokens, i);
            let price = *vector::borrow(&prices, i);
            let confidence = *vector::borrow(&confidences, i);

            assert!(price > 0, perp_types::e_invalid_price());

            if (table::contains(&oracle.prices, token)) {
                table::remove(&mut oracle.prices, token);
            };

            table::add(&mut oracle.prices, token, PriceData {
                price,
                timestamp,
                confidence,
            });

            i = i + 1;
        };
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    /// Get price with staleness check
    public fun get_price(
        oracle: &Oracle,
        token: String,
        clock: &Clock
    ): u64 {
        assert!(table::contains(&oracle.prices, token), perp_types::e_pair_not_found());

        let data = table::borrow(&oracle.prices, token);
        let current_time = clock::timestamp_ms(clock);
        let age = current_time - data.timestamp;

        assert!(age <= oracle.max_age_ms, perp_types::e_price_stale());

        data.price
    }

    /// Get price without staleness check (use carefully)
    public fun get_price_unsafe(oracle: &Oracle, token: String): u64 {
        assert!(table::contains(&oracle.prices, token), perp_types::e_pair_not_found());
        table::borrow(&oracle.prices, token).price
    }

    /// Get price from cache or oracle (for trading)
    public fun get_price_for_trading(
        oracle: &Oracle,
        token: String,
        clock: &Clock
    ): (u64, u64) {
        assert!(table::contains(&oracle.prices, token), perp_types::e_pair_not_found());

        let data = table::borrow(&oracle.prices, token);
        (data.price, data.timestamp)
    }

    /// Check if price is fresh
    public fun is_price_fresh(
        oracle: &Oracle,
        token: String,
        clock: &Clock
    ): bool {
        if (!table::contains(&oracle.prices, token)) {
            return false
        };

        let data = table::borrow(&oracle.prices, token);
        let age = clock::timestamp_ms(clock) - data.timestamp;
        age <= oracle.max_age_ms
    }

    /// Get price age
    public fun get_price_age(
        oracle: &Oracle,
        token: String,
        clock: &Clock
    ): u64 {
        assert!(table::contains(&oracle.prices, token), perp_types::e_pair_not_found());
        let data = table::borrow(&oracle.prices, token);
        clock::timestamp_ms(clock) - data.timestamp
    }

    // ============================================
    // HELPERS
    // ============================================

    fun calculate_deviation(old_price: u64, new_price: u64): u64 {
        let diff = if (new_price > old_price) {
            new_price - old_price
        } else {
            old_price - new_price
        };

        (diff * 10000) / old_price
    }

    /// Convert token amount to USD value
    public fun to_usd(
        oracle: &Oracle,
        token: String,
        amount: u64,
        decimals: u8,
        clock: &Clock
    ): u64 {
        let price = get_price(oracle, token, clock);
        let precision = perp_types::price_precision();

        // USD = amount * price / 10^decimals
        let mut divisor: u64 = 1;
        let mut i: u8 = 0;
        while (i < decimals) {
            divisor = divisor * 10;
            i = i + 1;
        };

        ((amount as u128) * (price as u128) / (divisor as u128) as u64)
    }

    // ============================================
    // TOKEN SYMBOL HELPERS
    // ============================================

    public fun btc_symbol(): String { std::string::utf8(b"BTC") }
    public fun eth_symbol(): String { std::string::utf8(b"ETH") }
    public fun oct_symbol(): String { std::string::utf8(b"OCT") }
    public fun usdt_symbol(): String { std::string::utf8(b"USDT") }
    public fun usdc_symbol(): String { std::string::utf8(b"USDC") }
}
