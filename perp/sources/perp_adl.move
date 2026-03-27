/// Auto-Deleveraging (ADL) system for when liquidations can't be filled
/// ADL reduces profitable positions to cover losses when insurance fund is insufficient
module perp::perp_adl {
    use one::object::{UID, ID};
    use one::tx_context::TxContext;
    use one::clock::{Self, Clock};
    use one::event;
    use one::table::{Self, Table};
    use std::string::String;
    use perp::perp_types;

    // ============================================
    // CONSTANTS
    // ============================================

    /// Number of ADL ranking buckets (1-5, where 5 is highest priority)
    const ADL_BUCKETS: u64 = 5;

    // ============================================
    // STRUCTS
    // ============================================

    /// Position ranking for ADL priority
    public struct ADLRanking has store, copy, drop {
        position_id: ID,
        trader: address,
        pair: String,
        is_long: bool,
        pnl_percent: u64,      // PnL as percentage of margin (scaled by 1e4)
        leverage: u64,
        bucket: u8,            // 1-5 ranking bucket
        notional_usd: u64,
    }

    /// ADL state for a pair
    public struct PairADLState has store {
        /// Long positions ranked by ADL priority
        long_rankings: vector<ADLRanking>,
        /// Short positions ranked by ADL priority
        short_rankings: vector<ADLRanking>,
        /// Total long notional that can be ADL'd
        total_long_notional: u64,
        /// Total short notional that can be ADL'd
        total_short_notional: u64,
        /// Last update timestamp
        last_update_ms: u64,
    }

    /// Main ADL manager
    public struct ADLManager has key {
        id: UID,
        admin: address,
        /// Per-pair ADL states
        pair_states: Table<String, PairADLState>,
        /// Is ADL enabled globally
        enabled: bool,
        /// Minimum PnL% to be eligible for ADL (bps)
        min_pnl_threshold_bps: u64,
        /// ADL execution cooldown (ms)
        cooldown_ms: u64,
        /// Last ADL execution per pair
        last_adl_time: Table<String, u64>,
        /// Total ADL events
        total_adl_count: u64,
        /// Total notional ADL'd
        total_adl_notional: u64,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct ADLManagerCreated has copy, drop {
        manager_id: ID,
        admin: address,
    }

    public struct ADLExecuted has copy, drop {
        pair: String,
        position_id: ID,
        trader: address,
        is_long: bool,
        size_reduced: u64,
        price: u64,
        pnl_realized: u64,
        is_profit: bool,
    }

    public struct ADLRankingUpdated has copy, drop {
        pair: String,
        long_count: u64,
        short_count: u64,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let manager = ADLManager {
            id: object::new(ctx),
            admin,
            pair_states: table::new(ctx),
            enabled: true,
            min_pnl_threshold_bps: 0, // Any profitable position can be ADL'd
            cooldown_ms: 1000, // 1 second cooldown
            last_adl_time: table::new(ctx),
            total_adl_count: 0,
            total_adl_notional: 0,
        };

        event::emit(ADLManagerCreated {
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
    // RANKING FUNCTIONS
    // ============================================

    /// Calculate ADL bucket (1-5) based on PnL% and leverage
    /// Higher bucket = higher priority for ADL
    /// Bucket is based on: PnL% * Leverage
    public fun calculate_bucket(pnl_percent: u64, leverage: u64): u8 {
        // ADL score = PnL% * Leverage
        let score = (pnl_percent * leverage) / 10000;

        if (score >= 50000) { 5 }      // Very high profit + leverage
        else if (score >= 30000) { 4 }
        else if (score >= 15000) { 3 }
        else if (score >= 5000) { 2 }
        else { 1 }                      // Low profit or low leverage
    }

    /// Update ADL ranking for a position
    public fun update_ranking(
        manager: &mut ADLManager,
        pair: String,
        position_id: ID,
        trader: address,
        is_long: bool,
        margin: u64,
        pnl: u64,
        is_profit: bool,
        leverage: u64,
        notional_usd: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Only profitable positions are in ADL queue
        if (!is_profit || pnl == 0) {
            // Remove from rankings if exists
            remove_from_rankings(manager, pair, position_id, is_long, ctx);
            return
        };

        // Calculate PnL percentage (scaled by 1e4)
        let pnl_percent = if (margin > 0) {
            (pnl * 10000) / margin
        } else {
            0
        };

        // Check minimum threshold
        if (pnl_percent < manager.min_pnl_threshold_bps) {
            remove_from_rankings(manager, pair, position_id, is_long, ctx);
            return
        };

        let bucket = calculate_bucket(pnl_percent, leverage);

        let ranking = ADLRanking {
            position_id,
            trader,
            pair,
            is_long,
            pnl_percent,
            leverage,
            bucket,
            notional_usd,
        };

        // Ensure pair state exists
        if (!table::contains(&manager.pair_states, pair)) {
            table::add(&mut manager.pair_states, pair, PairADLState {
                long_rankings: vector::empty(),
                short_rankings: vector::empty(),
                total_long_notional: 0,
                total_short_notional: 0,
                last_update_ms: clock::timestamp_ms(clock),
            });
        };

        let state = table::borrow_mut(&mut manager.pair_states, pair);

        // Remove old ranking if exists, then add new
        let rankings = if (is_long) {
            &mut state.long_rankings
        } else {
            &mut state.short_rankings
        };

        // Remove existing entry for this position
        let len = vector::length(rankings);
        let mut i = 0;
        let mut found_idx: u64 = len;
        while (i < len) {
            let r = vector::borrow(rankings, i);
            if (r.position_id == position_id) {
                found_idx = i;
                break
            };
            i = i + 1;
        };

        if (found_idx < len) {
            let old = vector::remove(rankings, found_idx);
            if (is_long) {
                state.total_long_notional = state.total_long_notional - old.notional_usd;
            } else {
                state.total_short_notional = state.total_short_notional - old.notional_usd;
            };
        };

        // Insert in sorted order (highest bucket first)
        let insert_idx = find_insert_position(rankings, bucket);
        vector::insert(rankings, ranking, insert_idx);

        if (is_long) {
            state.total_long_notional = state.total_long_notional + notional_usd;
        } else {
            state.total_short_notional = state.total_short_notional + notional_usd;
        };

        state.last_update_ms = clock::timestamp_ms(clock);
    }

    /// Find position to insert maintaining descending order by bucket
    fun find_insert_position(rankings: &vector<ADLRanking>, bucket: u8): u64 {
        let len = vector::length(rankings);
        let mut i = 0;
        while (i < len) {
            if (vector::borrow(rankings, i).bucket < bucket) {
                return i
            };
            i = i + 1;
        };
        len
    }

    /// Remove position from rankings
    fun remove_from_rankings(
        manager: &mut ADLManager,
        pair: String,
        position_id: ID,
        is_long: bool,
        _ctx: &mut TxContext
    ) {
        if (!table::contains(&manager.pair_states, pair)) {
            return
        };

        let state = table::borrow_mut(&mut manager.pair_states, pair);
        let rankings = if (is_long) {
            &mut state.long_rankings
        } else {
            &mut state.short_rankings
        };

        let len = vector::length(rankings);
        let mut i = 0;
        while (i < len) {
            let r = vector::borrow(rankings, i);
            if (r.position_id == position_id) {
                let removed = vector::remove(rankings, i);
                if (is_long) {
                    state.total_long_notional = state.total_long_notional - removed.notional_usd;
                } else {
                    state.total_short_notional = state.total_short_notional - removed.notional_usd;
                };
                break
            };
            i = i + 1;
        };
    }

    // ============================================
    // ADL EXECUTION
    // ============================================

    /// Get the next position to ADL for covering a losing position
    /// If liquidating a long, we ADL profitable shorts (and vice versa)
    public fun get_next_adl_target(
        manager: &ADLManager,
        pair: String,
        liquidating_is_long: bool,
    ): (bool, ID, address, u64) {
        // has_target, position_id, trader, notional
        if (!table::contains(&manager.pair_states, pair)) {
            return (false, object::id_from_address(@0x0), @0x0, 0)
        };

        let state = table::borrow(&manager.pair_states, pair);

        // If liquidating a long, ADL profitable shorts
        // If liquidating a short, ADL profitable longs
        let rankings = if (liquidating_is_long) {
            &state.short_rankings
        } else {
            &state.long_rankings
        };

        if (vector::length(rankings) == 0) {
            return (false, object::id_from_address(@0x0), @0x0, 0)
        };

        // Get highest priority (first in sorted list)
        let target = vector::borrow(rankings, 0);
        (true, target.position_id, target.trader, target.notional_usd)
    }

    /// Execute ADL on a position
    /// Returns the amount to reduce and updates internal state
    public fun execute_adl(
        manager: &mut ADLManager,
        pair: String,
        position_id: ID,
        trader: address,
        is_long: bool,
        size_to_reduce: u64,
        price: u64,
        pnl_realized: u64,
        is_profit: bool,
        clock: &Clock,
    ) {
        assert!(manager.enabled, perp_types::e_adl_disabled());

        // Check cooldown
        if (table::contains(&manager.last_adl_time, pair)) {
            let last_time = *table::borrow(&manager.last_adl_time, pair);
            let current_time = clock::timestamp_ms(clock);
            assert!(current_time >= last_time + manager.cooldown_ms, perp_types::e_adl_disabled());
        };

        // Update last ADL time
        if (table::contains(&manager.last_adl_time, pair)) {
            table::remove(&mut manager.last_adl_time, pair);
        };
        table::add(&mut manager.last_adl_time, pair, clock::timestamp_ms(clock));

        // Update stats
        manager.total_adl_count = manager.total_adl_count + 1;
        manager.total_adl_notional = manager.total_adl_notional + size_to_reduce;

        event::emit(ADLExecuted {
            pair,
            position_id,
            trader,
            is_long,
            size_reduced: size_to_reduce,
            price,
            pnl_realized,
            is_profit,
        });
    }

    /// Check if ADL can be executed
    public fun can_execute_adl(
        manager: &ADLManager,
        pair: String,
        clock: &Clock,
    ): bool {
        if (!manager.enabled) {
            return false
        };

        if (table::contains(&manager.last_adl_time, pair)) {
            let last_time = *table::borrow(&manager.last_adl_time, pair);
            let current_time = clock::timestamp_ms(clock);
            if (current_time < last_time + manager.cooldown_ms) {
                return false
            };
        };

        true
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    public entry fun set_enabled(
        manager: &mut ADLManager,
        enabled: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.enabled = enabled;
    }

    public entry fun set_min_pnl_threshold(
        manager: &mut ADLManager,
        threshold_bps: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.min_pnl_threshold_bps = threshold_bps;
    }

    public entry fun set_cooldown(
        manager: &mut ADLManager,
        cooldown_ms: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.cooldown_ms = cooldown_ms;
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    public fun is_enabled(manager: &ADLManager): bool {
        manager.enabled
    }

    public fun get_long_rankings_count(manager: &ADLManager, pair: String): u64 {
        if (!table::contains(&manager.pair_states, pair)) {
            return 0
        };
        vector::length(&table::borrow(&manager.pair_states, pair).long_rankings)
    }

    public fun get_short_rankings_count(manager: &ADLManager, pair: String): u64 {
        if (!table::contains(&manager.pair_states, pair)) {
            return 0
        };
        vector::length(&table::borrow(&manager.pair_states, pair).short_rankings)
    }

    public fun get_total_long_notional(manager: &ADLManager, pair: String): u64 {
        if (!table::contains(&manager.pair_states, pair)) {
            return 0
        };
        table::borrow(&manager.pair_states, pair).total_long_notional
    }

    public fun get_total_short_notional(manager: &ADLManager, pair: String): u64 {
        if (!table::contains(&manager.pair_states, pair)) {
            return 0
        };
        table::borrow(&manager.pair_states, pair).total_short_notional
    }

    public fun total_adl_count(manager: &ADLManager): u64 {
        manager.total_adl_count
    }

    public fun total_adl_notional(manager: &ADLManager): u64 {
        manager.total_adl_notional
    }

    /// Get ADL indicator (0-5) for a user's position
    /// Shows how likely their position is to be ADL'd
    public fun get_adl_indicator(
        manager: &ADLManager,
        pair: String,
        position_id: ID,
        is_long: bool,
    ): u8 {
        if (!table::contains(&manager.pair_states, pair)) {
            return 0
        };

        let state = table::borrow(&manager.pair_states, pair);
        let rankings = if (is_long) {
            &state.long_rankings
        } else {
            &state.short_rankings
        };

        let len = vector::length(rankings);
        let mut i = 0;
        while (i < len) {
            let r = vector::borrow(rankings, i);
            if (r.position_id == position_id) {
                return r.bucket
            };
            i = i + 1;
        };

        0 // Not in ADL queue
    }
}
