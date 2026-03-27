/// AI Football Manager Arena - Team NFT Module
/// Manages team creation, stats, upgrades, formations, and ownership
module leaguealpha::team_nft {
    use one::object::{Self, UID, ID};
    use one::transfer;
    use one::tx_context::{Self, TxContext};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::balance::{Self, Balance};
    use one::table::{Self, Table};
    use one::event;
    use std::string::{Self, String};

    // === Stats Constants ===
    const MIN_STAT: u8 = 1;
    const MAX_STAT: u8 = 100;
    const STARTING_STAT_TOTAL: u64 = 150;

    // === Formation Constants ===
    const FORMATION_433: u8 = 1;
    const FORMATION_442: u8 = 2;
    const FORMATION_541: u8 = 3;
    const FORMATION_352: u8 = 4;
    const FORMATION_4231: u8 = 5;

    // === Strategy Constants (Risk-Based) ===
    const STYLE_GEGENPRESSING: u8 = 1;  // +15 atk, -10 def, +10 atk if winning
    const STYLE_BALANCED: u8 = 2;       // No modifiers
    const STYLE_PARK_THE_BUS: u8 = 3;   // -15 atk, +20 def, draws more likely
    const STYLE_COUNTER: u8 = 4;        // +8 atk, +3 def, +15 atk vs >60 atk opponent
    const STYLE_TIKI_TAKA: u8 = 5;      // +5 atk, +5 def, +15 midfield
    const STYLE_LONG_BALL: u8 = 6;      // +10 atk, -5 def, bypasses midfield

    // === Commitment System ===
    const STRATEGY_LOCK_DURATION_MS: u64 = 3_600_000; // 1 hour

    // === Upgrade Costs ===
    const STAT_UPGRADE_BASE: u64 = 100_000_000; // 0.1 OCT per point at level 1
    const CREATION_FEE: u64 = 1_000_000_000;    // 1 OCT

    // === Error Codes ===
    const E_INVALID_STAT: u64 = 0;
    const E_STAT_EXCEEDS_TOTAL: u64 = 1;
    const E_INVALID_FORMATION: u64 = 2;
    const E_INVALID_STRATEGY: u64 = 3;
    const E_NOT_OWNER: u64 = 4;
    const E_INSUFFICIENT_PAYMENT: u64 = 5;
    const E_STAT_AT_MAX: u64 = 6;
    const E_TEAM_NOT_FOUND: u64 = 7;
    const E_STRATEGY_LOCKED: u64 = 8;

    // === Structs ===

    /// Team NFT (key+store, transferable)
    public struct TeamNFT has key, store {
        id: UID,
        name: String,

        // Core stats (1-100)
        attack: u8,
        defense: u8,
        midfield: u8,

        // Tactical settings
        formation: u8,
        strategy: u8,
        strategy_locked_at: u64, // Timestamp until which strategy is locked

        // Match record
        wins: u64,
        losses: u64,
        draws: u64,
        goals_for: u64,
        goals_against: u64,
        last_5_results: vector<u8>, // 1=win, 2=loss, 3=draw (most recent last)

        // Owner
        owner: address,

        // Metadata
        created_at: u64,
        total_matches: u64,
    }

    /// Team registry (singleton shared object)
    public struct TeamRegistry has key {
        id: UID,
        teams: vector<ID>,
        team_count: u64,
        admin: address,
        total_matches_played: u64,
        revenue_pool: Balance<OCT>,
    }

    /// Owner revenue claim (owned by team owner, holds OCT)
    public struct OwnerRevenue has key, store {
        id: UID,
        owner: address,
        team_id: ID,
        balance: Balance<OCT>,
    }

    // === Events ===

    public struct TeamCreated has copy, drop {
        team_id: ID,
        owner: address,
        name: String,
        attack: u8,
        defense: u8,
        midfield: u8,
        formation: u8,
        strategy: u8,
    }

    public struct TeamStatUpgraded has copy, drop {
        team_id: ID,
        stat_type: u8, // 1=attack, 2=defense, 3=midfield
        old_value: u8,
        new_value: u8,
        cost: u64,
    }

    public struct TeamFormationChanged has copy, drop {
        team_id: ID,
        old_formation: u8,
        new_formation: u8,
    }

    public struct TeamStrategyChanged has copy, drop {
        team_id: ID,
        old_strategy: u8,
        new_strategy: u8,
    }

    public struct TeamStatsUpdated has copy, drop {
        team_id: ID,
        wins: u64,
        losses: u64,
        draws: u64,
        goals_for: u64,
        goals_against: u64,
    }

    public struct OwnerRevenueClaimed has copy, drop {
        team_id: ID,
        owner: address,
        amount: u64,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let registry = TeamRegistry {
            id: object::new(ctx),
            teams: vector::empty<ID>(),
            team_count: 0,
            admin: tx_context::sender(ctx),
            total_matches_played: 0,
            revenue_pool: balance::zero<OCT>(),
        };
        transfer::share_object(registry);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Team Creation ===

    /// Create a new team NFT
    public entry fun create_team(
        registry: &mut TeamRegistry,
        name: vector<u8>,
        attack: u8,
        defense: u8,
        midfield: u8,
        formation: u8,
        strategy: u8,
        mut payment: Coin<OCT>,
        clock: &one::clock::Clock,
        ctx: &mut TxContext
    ) {
        // Validate stats
        assert!(attack >= MIN_STAT && attack <= MAX_STAT, E_INVALID_STAT);
        assert!(defense >= MIN_STAT && defense <= MAX_STAT, E_INVALID_STAT);
        assert!(midfield >= MIN_STAT && midfield <= MAX_STAT, E_INVALID_STAT);
        assert!(
            (attack as u64) + (defense as u64) + (midfield as u64) <= STARTING_STAT_TOTAL,
            E_STAT_EXCEEDS_TOTAL
        );

        // Validate formation
        assert!(formation >= FORMATION_433 && formation <= FORMATION_4231, E_INVALID_FORMATION);
        // Validate strategy
        assert!(
            (strategy >= STYLE_GEGENPRESSING && strategy <= STYLE_COUNTER) ||
            (strategy >= STYLE_TIKI_TAKA && strategy <= STYLE_LONG_BALL),
            E_INVALID_STRATEGY
        );

        // Validate payment
        assert!(coin::value(&payment) >= CREATION_FEE, E_INSUFFICIENT_PAYMENT);

        let sender = tx_context::sender(ctx);

        // Take creation fee
        let fee_coin = coin::split(&mut payment, CREATION_FEE, ctx);
        balance::join(&mut registry.revenue_pool, coin::into_balance(fee_coin));
        // Return change
        transfer::public_transfer(payment, sender);

        // Create team NFT
        let team = TeamNFT {
            id: object::new(ctx),
            name: string::utf8(name),
            attack,
            defense,
            midfield,
            formation,
            strategy,
            strategy_locked_at: 0,
            wins: 0,
            losses: 0,
            draws: 0,
            goals_for: 0,
            goals_against: 0,
            last_5_results: vector::empty(),
            owner: sender,
            created_at: one::clock::timestamp_ms(clock),
            total_matches: 0,
        };

        let team_id = object::id(&team);

        // Register in global registry
        vector::push_back(&mut registry.teams, team_id);
        registry.team_count = registry.team_count + 1;

        event::emit(TeamCreated {
            team_id,
            owner: sender,
            name: string::utf8(name),
            attack,
            defense,
            midfield,
            formation,
            strategy,
        });

        // Transfer NFT to owner
        transfer::public_transfer(team, sender);
    }

    // === Team Upgrades ===

    /// Upgrade a team stat by 1 point
    public entry fun upgrade_stat(
        team: &mut TeamNFT,
        registry: &mut TeamRegistry,
        stat_type: u8, // 1=attack, 2=defense, 3=midfield
        mut payment: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        assert!(team.owner == tx_context::sender(ctx), E_NOT_OWNER);
        assert!(stat_type >= 1 && stat_type <= 3, E_INVALID_STAT);

        let current_value = if (stat_type == 1) { team.attack }
        else if (stat_type == 2) { team.defense }
        else { team.midfield };

        assert!(current_value < MAX_STAT, E_STAT_AT_MAX);

        // Cost increases with current stat value (exponential)
        let cost = STAT_UPGRADE_BASE * (current_value as u64);
        assert!(coin::value(&payment) >= cost, E_INSUFFICIENT_PAYMENT);

        // Take payment into registry revenue pool
        let fee_coin = coin::split(&mut payment, cost, ctx);
        balance::join(&mut registry.revenue_pool, coin::into_balance(fee_coin));
        // Return change to sender
        transfer::public_transfer(payment, tx_context::sender(ctx));

        // Upgrade stat
        let new_value = current_value + 1;
        if (stat_type == 1) { team.attack = new_value; }
        else if (stat_type == 2) { team.defense = new_value; }
        else { team.midfield = new_value; };

        event::emit(TeamStatUpgraded {
            team_id: object::id(team),
            stat_type,
            old_value: current_value,
            new_value,
            cost,
        });
    }

    // === Tactical Settings ===

    /// Change team formation
    public entry fun set_formation(
        team: &mut TeamNFT,
        formation: u8,
        ctx: &TxContext
    ) {
        assert!(team.owner == tx_context::sender(ctx), E_NOT_OWNER);
        assert!(formation >= FORMATION_433 && formation <= FORMATION_4231, E_INVALID_FORMATION);

        let old = team.formation;
        team.formation = formation;

        event::emit(TeamFormationChanged {
            team_id: object::id(team),
            old_formation: old,
            new_formation: formation,
        });
    }

    /// Change team strategy (with 1-hour commitment lock)
    public entry fun set_strategy(
        team: &mut TeamNFT,
        strategy: u8,
        clock: &one::clock::Clock,
        ctx: &TxContext
    ) {
        assert!(team.owner == tx_context::sender(ctx), E_NOT_OWNER);
        assert!(
            (strategy >= STYLE_GEGENPRESSING && strategy <= STYLE_COUNTER) ||
            (strategy >= STYLE_TIKI_TAKA && strategy <= STYLE_LONG_BALL),
            E_INVALID_STRATEGY
        );

        let current_time = one::clock::timestamp_ms(clock);
        assert!(current_time >= team.strategy_locked_at, E_STRATEGY_LOCKED);

        let old = team.strategy;
        team.strategy = strategy;
        team.strategy_locked_at = current_time + STRATEGY_LOCK_DURATION_MS;

        event::emit(TeamStrategyChanged {
            team_id: object::id(team),
            old_strategy: old,
            new_strategy: strategy,
        });
    }

    // === Match Result Updates ===

    /// Update team stats after a match (called only by match engine)
    public(package) fun update_match_result(
        team: &mut TeamNFT,
        goals_scored: u8,
        goals_conceded: u8,
    ) {
        let gs = goals_scored as u64;
        let gc = goals_conceded as u64;

        team.goals_for = team.goals_for + gs;
        team.goals_against = team.goals_against + gc;
        team.total_matches = team.total_matches + 1;

        if (goals_scored > goals_conceded) {
            team.wins = team.wins + 1;
            add_result_to_history(team, 1); // win
        } else if (goals_scored < goals_conceded) {
            team.losses = team.losses + 1;
            add_result_to_history(team, 2); // loss
        } else {
            team.draws = team.draws + 1;
            add_result_to_history(team, 3); // draw
        };

        event::emit(TeamStatsUpdated {
            team_id: object::id(team),
            wins: team.wins,
            losses: team.losses,
            draws: team.draws,
            goals_for: team.goals_for,
            goals_against: team.goals_against,
        });
    }

    /// Add result to last_5_results, keeping only the most recent 5
    public(package) fun add_result_to_history(team: &mut TeamNFT, result: u8) {
        vector::push_back(&mut team.last_5_results, result);
        // Keep only last 5 results
        while (vector::length(&team.last_5_results) > 5) {
            vector::remove(&mut team.last_5_results, 0);
        };
    }

    // === Owner Revenue ===

    /// Allocate revenue to team owner
    public fun allocate_owner_revenue(
        _registry: &mut TeamRegistry,
        team: &TeamNFT,
        payment: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        let owner = team.owner;
        let revenue = OwnerRevenue {
            id: object::new(ctx),
            owner,
            team_id: object::id(team),
            balance: coin::into_balance(payment),
        };
        transfer::public_transfer(revenue, owner);
    }

    /// Claim accumulated owner revenue
    public entry fun claim_owner_revenue(
        revenue: OwnerRevenue,
        ctx: &mut TxContext
    ) {
        let OwnerRevenue { id, owner, team_id: _, balance } = revenue;
        assert!(owner == tx_context::sender(ctx), E_NOT_OWNER);

        let amount = balance::value(&balance);

        event::emit(OwnerRevenueClaimed {
            team_id: object::uid_to_inner(&id),
            owner,
            amount,
        });

        let payout = coin::from_balance(balance, ctx);
        transfer::public_transfer(payout, owner);
        object::delete(id);
    }

    // === View Functions ===

    public fun get_team_stats(team: &TeamNFT): (u8, u8, u8, u8, u8) {
        (team.attack, team.defense, team.midfield, team.formation, team.strategy)
    }

    public fun get_team_record(team: &TeamNFT): (u64, u64, u64, u64, u64) {
        (team.wins, team.losses, team.draws, team.goals_for, team.goals_against)
    }

    public fun get_team_name(team: &TeamNFT): String {
        team.name
    }

    public fun get_team_owner(team: &TeamNFT): address {
        team.owner
    }

    public fun get_team_id(team: &TeamNFT): ID {
        object::id(team)
    }

    public fun get_formation(team: &TeamNFT): u8 {
        team.formation
    }

    public fun get_strategy(team: &TeamNFT): u8 {
        team.strategy
    }

    public fun get_strategy_locked_at(team: &TeamNFT): u64 {
        team.strategy_locked_at
    }

    /// Check if strategy can currently be changed (not locked)
    public fun can_change_strategy(team: &TeamNFT, clock: &one::clock::Clock): bool {
        one::clock::timestamp_ms(clock) >= team.strategy_locked_at
    }

    /// Get last 5 results (1=win, 2=loss, 3=draw)
    public fun get_last_5_results(team: &TeamNFT): vector<u8> {
        team.last_5_results
    }

    /// Calculate momentum bonus from last 5 results
    /// Returns (atk_bonus, def_bonus, mid_bonus) - all unsigned, applied as additions
    /// 5 wins: +3 all (confidence), 4+ losses: skip (debuff handled by caller), 3+ draws: +5 def
    public fun get_momentum_bonus(team: &TeamNFT): (u64, u64, u64) {
        let results = &team.last_5_results;
        let len = vector::length(results);

        if (len == 0) {
            return (0, 0, 0)
        };

        let mut wins = 0u64;
        let mut losses = 0u64;
        let mut draws = 0u64;
        let mut i = 0;
        while (i < len) {
            let r = *vector::borrow(results, i);
            if (r == 1) wins = wins + 1
            else if (r == 2) losses = losses + 1
            else draws = draws + 1;
            i = i + 1;
        };

        if (wins == 5) {
            (3, 3, 3)       // +3 all stats (confidence)
        } else if (losses >= 4) {
            // Debuff handled separately via has_morale_debuff
            (0, 0, 0)
        } else if (draws >= 3) {
            (0, 5, 0)       // +5 defense (grinding draws)
        } else {
            (0, 0, 0)
        }
    }

    /// Check if team has a morale debuff from 4+ losses in last 5
    public fun has_morale_debuff(team: &TeamNFT): bool {
        let results = &team.last_5_results;
        let len = vector::length(results);
        if (len == 0) return false;

        let mut losses = 0u64;
        let mut i = 0;
        while (i < len) {
            if (*vector::borrow(results, i) == 2) losses = losses + 1;
            i = i + 1;
        };
        losses >= 4
    }

    public fun get_total_matches(team: &TeamNFT): u64 {
        team.total_matches
    }

    public fun get_team_strength(team: &TeamNFT): u64 {
        ((team.attack as u64) + (team.defense as u64) + (team.midfield as u64)) / 3
    }

    // === Admin Functions ===

    /// Withdraw registry revenue pool (admin only)
    public entry fun withdraw_registry_revenue(
        registry: &mut TeamRegistry,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == registry.admin, E_NOT_OWNER);
        let amount = balance::value(&registry.revenue_pool);
        assert!(amount > 0, E_INSUFFICIENT_PAYMENT);
        let coin_out = coin::from_balance(
            balance::withdraw_all(&mut registry.revenue_pool),
            ctx
        );
        transfer::public_transfer(coin_out, registry.admin);
    }

    // === View Functions ===

    public fun get_registry_info(registry: &TeamRegistry): (u64, u64) {
        (registry.team_count, registry.total_matches_played)
    }

    // === Constants Getters ===

    public fun formation_433(): u8 { FORMATION_433 }
    public fun formation_442(): u8 { FORMATION_442 }
    public fun formation_541(): u8 { FORMATION_541 }
    public fun formation_352(): u8 { FORMATION_352 }
    public fun formation_4231(): u8 { FORMATION_4231 }

    public fun style_gegenpressing(): u8 { STYLE_GEGENPRESSING }
    public fun style_balanced(): u8 { STYLE_BALANCED }
    public fun style_park_the_bus(): u8 { STYLE_PARK_THE_BUS }
    public fun style_counter(): u8 { STYLE_COUNTER }
    public fun style_tiki_taka(): u8 { STYLE_TIKI_TAKA }
    public fun style_long_ball(): u8 { STYLE_LONG_BALL }

    // Backward compat aliases
    public fun style_attacking(): u8 { STYLE_GEGENPRESSING }
    public fun style_defensive(): u8 { STYLE_PARK_THE_BUS }

    public fun max_stat(): u8 { MAX_STAT }
    public fun starting_stat_total(): u64 { STARTING_STAT_TOTAL }
    public fun creation_fee(): u64 { CREATION_FEE }
}
