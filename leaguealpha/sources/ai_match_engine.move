/// AI Football Manager Arena - Match Engine
/// Stat-weighted football match simulation with One Chain randomness
module leaguealpha::ai_match_engine {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::clock::{Self, Clock};
    use one::random::{Self, Random, RandomGenerator};
    use one::event;
    use std::option::{Self, Option};
    use leaguealpha::team_nft::{Self, TeamNFT};

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

    // === Home advantage ===
    const HOME_ADVANTAGE: u64 = 5;

    // === Error Codes ===
    const E_MATCH_NOT_SCHEDULED: u64 = 0;
    const E_MATCH_ALREADY_SETTLED: u64 = 1;
    const E_DEADLINE_NOT_REACHED: u64 = 2;
    const E_SAME_TEAM: u64 = 3;

    // === Structs ===

    /// Match result with full breakdown
    public struct MatchResult has store, copy, drop {
        match_id: u64,
        home_team_id: ID,
        away_team_id: ID,
        home_score: u8,
        away_score: u8,
        home_possession: u64,   // 0-100
        away_possession: u64,
        home_effective_atk: u64,
        home_effective_def: u64,
        away_effective_atk: u64,
        away_effective_def: u64,
    }

    /// Scheduled match (shared object)
    public struct ScheduledMatch has key {
        id: UID,
        match_id: u64,
        home_team_id: ID,
        away_team_id: ID,
        deadline: u64,
        settled: bool,
        result: Option<MatchResult>,
    }

    /// Match engine state (singleton shared)
    public struct MatchEngine has key {
        id: UID,
        next_match_id: u64,
        admin: address,
        total_matches: u64,
    }

    // === Events ===

    public struct MatchScheduled has copy, drop {
        match_id: u64,
        home_team_id: ID,
        away_team_id: ID,
        deadline: u64,
    }

    public struct MatchSettled has copy, drop {
        match_id: u64,
        home_team_id: ID,
        away_team_id: ID,
        home_score: u8,
        away_score: u8,
        home_possession: u64,
        away_possession: u64,
    }

    public struct RoundAutoScheduled has copy, drop {
        match_count: u64,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let engine = MatchEngine {
            id: object::new(ctx),
            next_match_id: 1,
            admin: tx_context::sender(ctx),
            total_matches: 0,
        };
        transfer::share_object(engine);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Match Scheduling ===

    /// Schedule a match between two teams
    public entry fun schedule_match(
        engine: &mut MatchEngine,
        home_team: &TeamNFT,
        away_team: &TeamNFT,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let home_id = team_nft::get_team_id(home_team);
        let away_id = team_nft::get_team_id(away_team);
        assert!(home_id != away_id, E_SAME_TEAM);

        let match_id = engine.next_match_id;
        engine.next_match_id = match_id + 1;
        engine.total_matches = engine.total_matches + 1;

        let deadline = clock::timestamp_ms(clock) + duration_ms;

        let scheduled = ScheduledMatch {
            id: object::new(ctx),
            match_id,
            home_team_id: home_id,
            away_team_id: away_id,
            deadline,
            settled: false,
            result: option::none(),
        };

        event::emit(MatchScheduled {
            match_id,
            home_team_id: home_id,
            away_team_id: away_id,
            deadline,
        });

        transfer::share_object(scheduled);
    }

    // === Match Settlement ===

    /// Settle a scheduled match using AI simulation + One Chain randomness
    #[allow(lint(public_random))]
    public entry fun settle_match(
        scheduled: &mut ScheduledMatch,
        home_team: &mut TeamNFT,
        away_team: &mut TeamNFT,
        _engine: &mut MatchEngine,
        random_obj: &Random,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!scheduled.settled, E_MATCH_ALREADY_SETTLED);
        assert!(clock::timestamp_ms(clock) >= scheduled.deadline, E_DEADLINE_NOT_REACHED);

        let mut generator = random::new_generator(random_obj, ctx);

        // Read team stats
        let (home_atk, home_def, home_mid, home_formation, home_strategy) = team_nft::get_team_stats(home_team);
        let (away_atk, away_def, away_mid, away_formation, away_strategy) = team_nft::get_team_stats(away_team);

        // Step 1: Formation modifiers
        let (home_atk_mod, home_def_mod) = formation_modifier(home_formation, away_formation);
        let (away_atk_mod, away_def_mod) = formation_modifier(away_formation, home_formation);

        // Step 2: Strategy modifiers (risk/reward based)
        let (home_str_atk, home_str_def) = strategy_modifier(home_strategy, away_strategy);
        let (away_str_atk, away_str_def) = strategy_modifier(away_strategy, home_strategy);

        // Step 2.5: Counter-Attack conditional bonus (+15 atk vs >60 atk opponent)
        let home_str_atk = if (home_strategy == STYLE_COUNTER) {
            counter_attack_bonus(away_atk)
        } else { home_str_atk };
        let away_str_atk = if (away_strategy == STYLE_COUNTER) {
            counter_attack_bonus(home_atk)
        } else { away_str_atk };

        // Step 2.6: Gegenpressing conditional bonus (+10 atk if team attack > opponent attack)
        let home_str_atk = if (home_strategy == STYLE_GEGENPRESSING && home_atk > away_atk) {
            home_str_atk + 10
        } else { home_str_atk };
        let away_str_atk = if (away_strategy == STYLE_GEGENPRESSING && away_atk > home_atk) {
            away_str_atk + 10
        } else { away_str_atk };

        // Step 3: Formation-Strategy synergy bonuses
        let (home_syn_atk, home_syn_def) = formation_strategy_synergy(home_formation, home_strategy);
        let (away_syn_atk, away_syn_def) = formation_strategy_synergy(away_formation, away_strategy);

        // Step 4: Momentum bonuses from recent form
        let (home_mom_atk, home_mom_def, home_mom_mid) = team_nft::get_momentum_bonus(home_team);
        let (away_mom_atk, away_mom_def, away_mom_mid) = team_nft::get_momentum_bonus(away_team);

        // Apply morale debuff (-2 all stats if 4+ losses in last 5)
        let home_morale_debuff = if (team_nft::has_morale_debuff(home_team)) { 2 } else { 0 };
        let away_morale_debuff = if (team_nft::has_morale_debuff(away_team)) { 2 } else { 0 };

        // Step 5: Midfield with Tiki-Taka bonus and momentum
        let home_mid_final = clamp(
            (home_mid as u64) + if (home_strategy == STYLE_TIKI_TAKA) { 15 } else { 0 }
                + home_mom_mid - home_morale_debuff,
            1, 100
        );
        let away_mid_final = clamp(
            (away_mid as u64) + if (away_strategy == STYLE_TIKI_TAKA) { 15 } else { 0 }
                + away_mom_mid - away_morale_debuff,
            1, 100
        );

        // Step 6: Calculate penalties (old-style tradeoffs baked into new strategies)
        let home_def_penalty = if (home_strategy == STYLE_GEGENPRESSING) { 10 } else if (home_strategy == STYLE_LONG_BALL) { 5 } else { 0 };
        let home_atk_penalty = if (home_strategy == STYLE_PARK_THE_BUS) { 15 } else { 0 };
        let away_def_penalty = if (away_strategy == STYLE_GEGENPRESSING) { 10 } else if (away_strategy == STYLE_LONG_BALL) { 5 } else { 0 };
        let away_atk_penalty = if (away_strategy == STYLE_PARK_THE_BUS) { 15 } else { 0 };

        // Step 7: Effective stats (with home advantage, synergy, momentum, penalties)
        let home_effective_atk = clamp(
            (home_atk as u64) + home_atk_mod + home_str_atk + home_syn_atk + HOME_ADVANTAGE
                - home_atk_penalty + home_mom_atk - home_morale_debuff,
            1, 100
        );
        let home_effective_def = clamp(
            (home_def as u64) + home_def_mod + home_str_def + home_syn_def + HOME_ADVANTAGE
                - home_def_penalty + home_mom_def - home_morale_debuff,
            1, 100
        );
        let away_effective_atk = clamp(
            (away_atk as u64) + away_atk_mod + away_str_atk + away_syn_atk
                - away_atk_penalty + away_mom_atk - away_morale_debuff,
            1, 100
        );
        let away_effective_def = clamp(
            (away_def as u64) + away_def_mod + away_str_def + away_syn_def
                - away_def_penalty + away_mom_def - away_morale_debuff,
            1, 100
        );

        // Step 8: Midfield control (with Long Ball bypass)
        let (home_possession, away_possession) = calculate_possession(
            home_mid_final, away_mid_final, home_strategy, away_strategy
        );

        // Step 9: Chances created
        let home_chances = (home_effective_atk * home_possession) / 100;
        let away_chances = (away_effective_atk * away_possession) / 100;

        // Step 10: Generate scores (Park the Bus increases draw likelihood)
        let home_draw_bias = if (home_strategy == STYLE_PARK_THE_BUS) { 1 } else { 0 };
        let away_draw_bias = if (away_strategy == STYLE_PARK_THE_BUS) { 1 } else { 0 };

        let home_score = generate_goals_with_bias(
            &mut generator, home_chances, away_effective_def, away_draw_bias
        );
        let away_score = generate_goals_with_bias(
            &mut generator, away_chances, home_effective_def, home_draw_bias
        );

        // Create result
        let result = MatchResult {
            match_id: scheduled.match_id,
            home_team_id: scheduled.home_team_id,
            away_team_id: scheduled.away_team_id,
            home_score,
            away_score,
            home_possession,
            away_possession,
            home_effective_atk,
            home_effective_def,
            away_effective_atk,
            away_effective_def,
        };

        // Store result
        scheduled.result = option::some(result);
        scheduled.settled = true;

        // Update team stats
        team_nft::update_match_result(home_team, home_score, away_score);
        team_nft::update_match_result(away_team, away_score, home_score);

        event::emit(MatchSettled {
            match_id: scheduled.match_id,
            home_team_id: scheduled.home_team_id,
            away_team_id: scheduled.away_team_id,
            home_score,
            away_score,
            home_possession,
            away_possession,
        });
    }

    // === Formation Modifiers ===

    /// Returns (attack_bonus, defense_bonus) for home team
    /// All values are positive bonuses. Penalties are applied via opponent's bonus.
    fun formation_modifier(home_formation: u8, away_formation: u8): (u64, u64) {
        // Rock-paper-scissors formation matchups
        if (home_formation == FORMATION_433) {
            if (away_formation == FORMATION_352) {
                (10, 0)  // 433 beats 352 (exploit flanks)
            } else if (away_formation == FORMATION_541) {
                (0, 0)   // 433 neutral vs 541 (bus parking)
            } else if (away_formation == FORMATION_4231) {
                (5, 0)
            } else {
                (3, 0)
            }
        } else if (home_formation == FORMATION_442) {
            if (away_formation == FORMATION_4231) {
                (8, 5)   // 442 beats 4231
            } else if (away_formation == FORMATION_433) {
                (0, 0)
            } else if (away_formation == FORMATION_541) {
                (5, 0)
            } else {
                (3, 0)
            }
        } else if (home_formation == FORMATION_541) {
            if (away_formation == FORMATION_433) {
                (0, 12)  // 541 beats 433 (defensive wall)
            } else if (away_formation == FORMATION_352) {
                (0, 0)   // 541 loses to 352 (no bonus)
            } else {
                (0, 5)
            }
        } else if (home_formation == FORMATION_352) {
            if (away_formation == FORMATION_541) {
                (8, 3)   // 352 beats 541 (midfield dominance)
            } else if (away_formation == FORMATION_433) {
                (0, 0)   // 352 loses to 433 (no bonus)
            } else {
                (3, 0)
            }
        } else if (home_formation == FORMATION_4231) {
            if (away_formation == FORMATION_433) {
                (3, 5)
            } else if (away_formation == FORMATION_442) {
                (0, 0)
            } else {
                (3, 3)
            }
        } else {
            (0, 0)
        }
    }

    // === Strategy Modifiers (Risk-Based) ===

    /// Returns (attack_bonus, defense_bonus) for team
    /// Each strategy has upside + downside creating real tradeoffs
    fun strategy_modifier(team_strategy: u8, _opponent_strategy: u8): (u64, u64) {
        if (team_strategy == STYLE_GEGENPRESSING) {
            (15, 0) // +15 atk, -10 def (penalty applied in settle_match)
        } else if (team_strategy == STYLE_BALANCED) {
            (0, 0)  // No modifiers
        } else if (team_strategy == STYLE_PARK_THE_BUS) {
            (0, 20) // -15 atk (penalty applied in settle_match), +20 def
        } else if (team_strategy == STYLE_COUNTER) {
            // +15 atk vs teams with >60 attack, otherwise +8 atk, +3 def
            (15, 3) // Conditional vs high-attack handled below
        } else if (team_strategy == STYLE_TIKI_TAKA) {
            (5, 5)  // +5 atk, +5 def, +15 midfield (applied in settle_match)
        } else if (team_strategy == STYLE_LONG_BALL) {
            (10, 0) // +10 atk, -5 def (penalty applied in settle_match), bypasses midfield
        } else {
            (0, 0)
        }
    }

    /// Get Counter-Attack conditional bonus against high-attack opponents (>60 atk)
    /// Returns additional attack bonus if opponent has high attack
    public fun counter_attack_bonus(opponent_atk: u8): u64 {
        if (opponent_atk > 60) { 15 } else { 8 }
    }

    // === Formation-Strategy Synergy ===

    /// Returns (atk_bonus, def_bonus) for optimal formation-strategy pairings
    /// Best Formation → Strategy gets synergy bonus
    fun formation_strategy_synergy(formation: u8, strategy: u8): (u64, u64) {
        if (strategy == STYLE_TIKI_TAKA && formation == FORMATION_4231) {
            (5, 5)  // +5 all stats
        } else if (strategy == STYLE_GEGENPRESSING && formation == FORMATION_433) {
            (8, 0)  // +8 attack
        } else if (strategy == STYLE_COUNTER && formation == FORMATION_541) {
            (0, 10) // +10 defense
        } else if (strategy == STYLE_LONG_BALL && formation == FORMATION_352) {
            (10, 0) // +10 attack
        } else if (strategy == STYLE_PARK_THE_BUS && formation == FORMATION_541) {
            (0, 15) // +15 defense
        } else {
            (0, 0)
        }
    }

    // === Possession with Long Ball Bypass ===

    /// Calculate possession, accounting for Long Ball midfield bypass
    /// Long Ball reduces opponent midfield contribution by 50%
    fun calculate_possession(
        home_mid: u64,
        away_mid: u64,
        home_strategy: u8,
        away_strategy: u8,
    ): (u64, u64) {
        let home_mid_weight = if (away_strategy == STYLE_LONG_BALL) {
            home_mid * 50 / 100 // Opponent Long Ball reduces your midfield by 50%
        } else {
            home_mid
        };

        let away_mid_weight = if (home_strategy == STYLE_LONG_BALL) {
            away_mid * 50 / 100 // Your Long Ball reduces opponent midfield by 50%
        } else {
            away_mid
        };

        let total = home_mid_weight + away_mid_weight;
        if (total == 0) {
            (50, 50)
        } else {
            let home_poss = (home_mid_weight * 100) / total;
            (home_poss, 100 - home_poss)
        }
    }

    // === Goal Generation ===

    /// Generate goals with optional draw bias (Park the Bus effect)
    /// draw_bias > 0 reduces goal probability, making 0-0 and 1-1 more likely
    fun generate_goals_with_bias(
        generator: &mut RandomGenerator,
        chances: u64,
        opponent_defense: u64,
        draw_bias: u64
    ): u8 {
        // Park the Bus reduces attack effectiveness
        let effective_chances = if (draw_bias > 0 && chances > 10) {
            chances - 10
        } else {
            chances
        };

        // Attack score determines goal probability
        let attack_score = if (effective_chances > opponent_defense) {
            (effective_chances - opponent_defense) * 2
        } else {
            0
        };

        let roll = random::generate_u64_in_range(generator, 0, 200);

        if (roll < 15 + attack_score) {
            // Hat trick (very rare, needs high attack)
            if (attack_score > 40) { 3 } else { 2 }
        } else if (roll < 50 + attack_score) {
            2  // Brace
        } else if (roll < 120 + attack_score) {
            1  // Single goal
        } else {
            0  // Clean sheet
        }
    }

    // === Utility ===

    fun clamp(value: u64, min: u64, max: u64): u64 {
        if (value < min) { min }
        else if (value > max) { max }
        else { value }
    }

    // === View Functions ===

    public fun is_match_settled(scheduled: &ScheduledMatch): bool {
        scheduled.settled
    }

    public fun get_match_id(scheduled: &ScheduledMatch): u64 {
        scheduled.match_id
    }

    public fun get_match_teams(scheduled: &ScheduledMatch): (ID, ID) {
        (scheduled.home_team_id, scheduled.away_team_id)
    }

    public fun get_match_deadline(scheduled: &ScheduledMatch): u64 {
        scheduled.deadline
    }

    public fun get_match_result(scheduled: &ScheduledMatch): &Option<MatchResult> {
        &scheduled.result
    }

    public fun get_result_scores(result: &MatchResult): (u8, u8) {
        (result.home_score, result.away_score)
    }

    public fun get_result_possession(result: &MatchResult): (u64, u64) {
        (result.home_possession, result.away_possession)
    }

    public fun get_match_outcome(scheduled: &ScheduledMatch): u8 {
        assert!(scheduled.settled, E_MATCH_NOT_SCHEDULED);
        let result = option::borrow(&scheduled.result);
        if (result.home_score > result.away_score) { 1 }      // HOME_WIN
        else if (result.away_score > result.home_score) { 2 }  // AWAY_WIN
        else { 3 }                                              // DRAW
    }

    public fun get_match_summary(scheduled: &ScheduledMatch): (u8, u8, u64, u64) {
        assert!(scheduled.settled, E_MATCH_NOT_SCHEDULED);
        let result = option::borrow(&scheduled.result);
        (result.home_score, result.away_score, result.home_possession, result.away_possession)
    }
}
