/// Pair and fee configuration management (based on Astex LibPairsManager + LibFeeManager)
module perp::perp_config {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::table::{Self, Table};
    use one::event;
    use std::string::String;
    use perp::perp_types::{Self, LeverageMargin, FeeConfig, SlippageConfig};

    // ============================================
    // STRUCTS
    // ============================================

    /// Trading pair configuration
    public struct PairConfig has store {
        name: String,                   // e.g., "BTC/USD"
        base: String,                   // e.g., "BTC"
        pair_type: u8,                  // crypto/forex/etc
        status: u8,                     // active/close-only/closed
        fee_config_index: u16,
        slippage_config_index: u16,
        max_long_oi_usd: u64,
        max_short_oi_usd: u64,
        current_long_oi_usd: u64,
        current_short_oi_usd: u64,
        funding_fee_per_block_p: u64,   // 1e18
        min_funding_fee_r: u64,         // 1e18
        max_funding_fee_r: u64,         // 1e18
        long_holding_fee_rate: u64,     // 1e12
        short_holding_fee_rate: u64,    // 1e12
        leverage_margins: Table<u16, LeverageMargin>,
        max_tier: u16,
    }

    /// Configuration manager
    public struct ConfigManager has key {
        id: UID,
        admin: address,
        fee_configs: Table<u16, FeeConfig>,
        slippage_configs: Table<u16, SlippageConfig>,
        pairs: Table<String, PairConfig>,
        pair_bases: vector<String>,
        dao_address: address,
        revenue_address: address,
        trading_enabled: bool,
        min_position_usd: u64,          // Minimum position size
        max_position_pct: u64,          // Max % of pool per position (bps)
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct ConfigManagerCreated has copy, drop {
        manager_id: ID,
        admin: address,
    }

    public struct FeeConfigAdded has copy, drop {
        index: u16,
        open_fee_p: u16,
        close_fee_p: u16,
    }

    public struct SlippageConfigAdded has copy, drop {
        index: u16,
        name: String,
    }

    public struct PairAdded has copy, drop {
        base: String,
        name: String,
        pair_type: u8,
    }

    public struct PairStatusUpdated has copy, drop {
        base: String,
        old_status: u8,
        new_status: u8,
    }

    public struct PairOiUpdated has copy, drop {
        base: String,
        max_long_oi: u64,
        max_short_oi: u64,
    }

    public struct LeverageMarginsUpdated has copy, drop {
        base: String,
        max_tier: u16,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let mut manager = ConfigManager {
            id: object::new(ctx),
            admin,
            fee_configs: table::new(ctx),
            slippage_configs: table::new(ctx),
            pairs: table::new(ctx),
            pair_bases: vector::empty(),
            dao_address: admin,
            revenue_address: admin,
            trading_enabled: true,
            min_position_usd: 10_000_000_000,   // $10 minimum
            max_position_pct: 1000,              // 10% of pool max
        };

        // Default fee config (index 0): 0.08% open/close
        let default_fee = perp_types::new_fee_config(
            std::string::utf8(b"Default"),
            0,
            8,      // 0.08% open
            8,      // 0.08% close
            0,      // no PnL share
            0,      // no min close fee
        );
        table::add(&mut manager.fee_configs, 0, default_fee);

        // Default slippage config (index 0)
        let default_slippage = perp_types::new_slippage_config(
            std::string::utf8(b"Default"),
            0,
            1_000_000_000_000_000,  // $1M depth above
            1_000_000_000_000_000,  // $1M depth below
            0,                       // no base slippage
            0,
            100_000_000_000_000,    // $100k threshold
            100_000_000_000_000,
        );
        table::add(&mut manager.slippage_configs, 0, default_slippage);

        event::emit(ConfigManagerCreated {
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
    // ADMIN - FEE CONFIG
    // ============================================

    public entry fun add_fee_config(
        manager: &mut ConfigManager,
        index: u16,
        name: String,
        open_fee_p: u16,
        close_fee_p: u16,
        share_p: u32,
        min_close_fee_p: u32,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(!table::contains(&manager.fee_configs, index), perp_types::e_fee_config_not_found());

        let config = perp_types::new_fee_config(name, index, open_fee_p, close_fee_p, share_p, min_close_fee_p);
        table::add(&mut manager.fee_configs, index, config);

        event::emit(FeeConfigAdded { index, open_fee_p, close_fee_p });
    }

    public entry fun update_fee_config(
        manager: &mut ConfigManager,
        index: u16,
        open_fee_p: u16,
        close_fee_p: u16,
        share_p: u32,
        min_close_fee_p: u32,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.fee_configs, index), perp_types::e_fee_config_not_found());

        table::remove(&mut manager.fee_configs, index);
        let name = std::string::utf8(b"Updated");
        let config = perp_types::new_fee_config(name, index, open_fee_p, close_fee_p, share_p, min_close_fee_p);
        table::add(&mut manager.fee_configs, index, config);
    }

    // ============================================
    // ADMIN - SLIPPAGE CONFIG
    // ============================================

    public entry fun add_slippage_config(
        manager: &mut ConfigManager,
        index: u16,
        name: String,
        one_pct_depth_above: u64,
        one_pct_depth_below: u64,
        slippage_long_p: u16,
        slippage_short_p: u16,
        long_threshold: u64,
        short_threshold: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(!table::contains(&manager.slippage_configs, index), perp_types::e_slippage_config_not_found());

        let config = perp_types::new_slippage_config(
            name, index,
            one_pct_depth_above, one_pct_depth_below,
            slippage_long_p, slippage_short_p,
            long_threshold, short_threshold,
        );
        table::add(&mut manager.slippage_configs, index, config);

        event::emit(SlippageConfigAdded { index, name });
    }

    // ============================================
    // ADMIN - PAIR MANAGEMENT
    // ============================================

    public entry fun add_pair(
        manager: &mut ConfigManager,
        name: String,
        base: String,
        pair_type: u8,
        fee_config_index: u16,
        slippage_config_index: u16,
        max_long_oi_usd: u64,
        max_short_oi_usd: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(!table::contains(&manager.pairs, base), perp_types::e_pair_exists());
        assert!(table::contains(&manager.fee_configs, fee_config_index), perp_types::e_fee_config_not_found());
        assert!(table::contains(&manager.slippage_configs, slippage_config_index), perp_types::e_slippage_config_not_found());

        let pair = PairConfig {
            name,
            base,
            pair_type,
            status: perp_types::pair_active(),
            fee_config_index,
            slippage_config_index,
            max_long_oi_usd,
            max_short_oi_usd,
            current_long_oi_usd: 0,
            current_short_oi_usd: 0,
            funding_fee_per_block_p: 0,
            min_funding_fee_r: 0,
            max_funding_fee_r: 0,
            long_holding_fee_rate: 0,
            short_holding_fee_rate: 0,
            leverage_margins: table::new(ctx),
            max_tier: 0,
        };

        table::add(&mut manager.pairs, base, pair);
        vector::push_back(&mut manager.pair_bases, base);

        event::emit(PairAdded { base, name, pair_type });
    }

    /// Set leverage margin tiers for a pair
    public entry fun set_leverage_margins(
        manager: &mut ConfigManager,
        base: String,
        tiers: vector<u16>,
        notionals: vector<u64>,
        max_leverages: vector<u16>,
        initial_lost_ps: vector<u16>,
        liq_lost_ps: vector<u16>,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.pairs, base), perp_types::e_pair_not_found());

        let pair = table::borrow_mut(&mut manager.pairs, base);
        let len = vector::length(&tiers);

        // Clear old margins
        let mut i: u16 = 1;
        while (i <= pair.max_tier) {
            if (table::contains(&pair.leverage_margins, i)) {
                table::remove(&mut pair.leverage_margins, i);
            };
            i = i + 1;
        };

        // Add new margins
        let mut j: u64 = 0;
        while (j < len) {
            let tier = *vector::borrow(&tiers, j);
            let margin = perp_types::new_leverage_margin(
                *vector::borrow(&notionals, j),
                tier,
                *vector::borrow(&max_leverages, j),
                *vector::borrow(&initial_lost_ps, j),
                *vector::borrow(&liq_lost_ps, j),
            );
            table::add(&mut pair.leverage_margins, tier, margin);
            j = j + 1;
        };

        pair.max_tier = (len as u16);

        event::emit(LeverageMarginsUpdated { base, max_tier: pair.max_tier });
    }

    public entry fun update_pair_status(
        manager: &mut ConfigManager,
        base: String,
        status: u8,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.pairs, base), perp_types::e_pair_not_found());

        let pair = table::borrow_mut(&mut manager.pairs, base);
        let old_status = pair.status;
        pair.status = status;

        event::emit(PairStatusUpdated { base, old_status, new_status: status });
    }

    public entry fun update_pair_max_oi(
        manager: &mut ConfigManager,
        base: String,
        max_long_oi_usd: u64,
        max_short_oi_usd: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.pairs, base), perp_types::e_pair_not_found());

        let pair = table::borrow_mut(&mut manager.pairs, base);
        pair.max_long_oi_usd = max_long_oi_usd;
        pair.max_short_oi_usd = max_short_oi_usd;

        event::emit(PairOiUpdated { base, max_long_oi: max_long_oi_usd, max_short_oi: max_short_oi_usd });
    }

    public entry fun update_pair_funding_config(
        manager: &mut ConfigManager,
        base: String,
        funding_fee_per_block_p: u64,
        min_funding_fee_r: u64,
        max_funding_fee_r: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.pairs, base), perp_types::e_pair_not_found());

        let pair = table::borrow_mut(&mut manager.pairs, base);
        pair.funding_fee_per_block_p = funding_fee_per_block_p;
        pair.min_funding_fee_r = min_funding_fee_r;
        pair.max_funding_fee_r = max_funding_fee_r;
    }

    public entry fun update_pair_holding_fees(
        manager: &mut ConfigManager,
        base: String,
        long_rate: u64,
        short_rate: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.pairs, base), perp_types::e_pair_not_found());

        let pair = table::borrow_mut(&mut manager.pairs, base);
        pair.long_holding_fee_rate = long_rate;
        pair.short_holding_fee_rate = short_rate;
    }

    public entry fun set_dao_address(
        manager: &mut ConfigManager,
        addr: address,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.dao_address = addr;
    }

    public entry fun set_revenue_address(
        manager: &mut ConfigManager,
        addr: address,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.revenue_address = addr;
    }

    public entry fun set_trading_enabled(
        manager: &mut ConfigManager,
        enabled: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.trading_enabled = enabled;
    }

    // ============================================
    // OI TRACKING (called by trading module)
    // ============================================

    public fun increase_oi(
        manager: &mut ConfigManager,
        base: String,
        is_long: bool,
        amount_usd: u64
    ) {
        let pair = table::borrow_mut(&mut manager.pairs, base);
        if (is_long) {
            pair.current_long_oi_usd = pair.current_long_oi_usd + amount_usd;
        } else {
            pair.current_short_oi_usd = pair.current_short_oi_usd + amount_usd;
        };
    }

    public fun decrease_oi(
        manager: &mut ConfigManager,
        base: String,
        is_long: bool,
        amount_usd: u64
    ) {
        let pair = table::borrow_mut(&mut manager.pairs, base);
        if (is_long) {
            pair.current_long_oi_usd = if (pair.current_long_oi_usd >= amount_usd) {
                pair.current_long_oi_usd - amount_usd
            } else { 0 };
        } else {
            pair.current_short_oi_usd = if (pair.current_short_oi_usd >= amount_usd) {
                pair.current_short_oi_usd - amount_usd
            } else { 0 };
        };
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    public fun get_max_leverage(
        manager: &ConfigManager,
        base: String,
        notional_usd: u64
    ): u16 {
        let pair = table::borrow(&manager.pairs, base);

        let mut i: u16 = 1;
        while (i <= pair.max_tier) {
            if (table::contains(&pair.leverage_margins, i)) {
                let margin = table::borrow(&pair.leverage_margins, i);
                if (notional_usd <= perp_types::lm_notional(margin)) {
                    return perp_types::lm_max_leverage(margin)
                };
            };
            i = i + 1;
        };

        // Default if no tiers: 50x
        50
    }

    public fun get_liquidation_threshold(
        manager: &ConfigManager,
        base: String,
        notional_usd: u64
    ): u16 {
        let pair = table::borrow(&manager.pairs, base);

        let mut i: u16 = 1;
        while (i <= pair.max_tier) {
            if (table::contains(&pair.leverage_margins, i)) {
                let margin = table::borrow(&pair.leverage_margins, i);
                if (notional_usd <= perp_types::lm_notional(margin)) {
                    return perp_types::lm_liq_lost_p(margin)
                };
            };
            i = i + 1;
        };

        9500 // Default 95%
    }

    public fun get_fee_config(manager: &ConfigManager, base: String): FeeConfig {
        let pair = table::borrow(&manager.pairs, base);
        *table::borrow(&manager.fee_configs, pair.fee_config_index)
    }

    public fun get_slippage_config(manager: &ConfigManager, base: String): SlippageConfig {
        let pair = table::borrow(&manager.pairs, base);
        *table::borrow(&manager.slippage_configs, pair.slippage_config_index)
    }

    public fun can_increase_oi(
        manager: &ConfigManager,
        base: String,
        is_long: bool,
        amount_usd: u64
    ): bool {
        let pair = table::borrow(&manager.pairs, base);

        if (pair.status != perp_types::pair_active()) {
            return false
        };

        if (is_long) {
            pair.current_long_oi_usd + amount_usd <= pair.max_long_oi_usd
        } else {
            pair.current_short_oi_usd + amount_usd <= pair.max_short_oi_usd
        }
    }

    public fun calculate_slippage(
        manager: &ConfigManager,
        base: String,
        is_long: bool,
        notional_usd: u64
    ): u64 {
        let pair = table::borrow(&manager.pairs, base);
        let config = table::borrow(&manager.slippage_configs, pair.slippage_config_index);

        let (threshold, depth, base_slip) = if (is_long) {
            (perp_types::sc_long_threshold(config), perp_types::sc_one_pct_depth_above(config), perp_types::sc_slippage_long_p(config))
        } else {
            (perp_types::sc_short_threshold(config), perp_types::sc_one_pct_depth_below(config), perp_types::sc_slippage_short_p(config))
        };

        if (notional_usd <= threshold) {
            return (base_slip as u64)
        };

        let excess = notional_usd - threshold;
        let dynamic = if (depth > 0) { (excess * 100) / depth } else { 0 };

        (base_slip as u64) + dynamic
    }

    public fun get_holding_fee_rate(
        manager: &ConfigManager,
        base: String,
        is_long: bool
    ): u64 {
        let pair = table::borrow(&manager.pairs, base);
        if (is_long) { pair.long_holding_fee_rate } else { pair.short_holding_fee_rate }
    }

    public fun pair_exists(manager: &ConfigManager, base: String): bool {
        table::contains(&manager.pairs, base)
    }

    public fun is_pair_active(manager: &ConfigManager, base: String): bool {
        if (!table::contains(&manager.pairs, base)) { return false };
        table::borrow(&manager.pairs, base).status == perp_types::pair_active()
    }

    public fun is_trading_enabled(manager: &ConfigManager): bool {
        manager.trading_enabled
    }

    public fun admin(manager: &ConfigManager): address { manager.admin }
    public fun dao_address(manager: &ConfigManager): address { manager.dao_address }
    public fun revenue_address(manager: &ConfigManager): address { manager.revenue_address }
    public fun min_position_usd(manager: &ConfigManager): u64 { manager.min_position_usd }
    public fun max_position_pct(manager: &ConfigManager): u64 { manager.max_position_pct }

    public fun get_pair_oi(manager: &ConfigManager, base: String): (u64, u64, u64, u64) {
        let pair = table::borrow(&manager.pairs, base);
        (pair.current_long_oi_usd, pair.current_short_oi_usd, pair.max_long_oi_usd, pair.max_short_oi_usd)
    }

    public fun get_funding_config(manager: &ConfigManager, base: String): (u64, u64, u64) {
        let pair = table::borrow(&manager.pairs, base);
        (pair.funding_fee_per_block_p, pair.min_funding_fee_r, pair.max_funding_fee_r)
    }
}
