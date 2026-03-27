/// Sports Betting Pool - Per-Match Fixed Odds Model
module leaguealpha::betting_pool {
    use one::object::{Self, UID};
    use one::transfer;
    use one::tx_context::{Self, TxContext};
    use one::coin::{Self, Coin};
    use one::balance::{Self, Balance};
    use one::oct::OCT;
    use one::table::{Self, Table};
    use one::event;
    use leaguealpha::game_engine::{Self, MatchData};
    use leaguealpha::team_nft::{Self, TeamNFT};
    use leaguealpha::ai_match_engine::{Self, ScheduledMatch};

    // === Constants ===

    const PROTOCOL_FEE_BPS: u64 = 500; // 5%
    const SEASON_POOL_SHARE_BPS: u64 = 200; // 2%

    // Seeding per match (in MIST: 1 OCT = 1_000_000_000 MIST)
    const SEED_PER_MATCH: u64 = 3_000_000_000_000; // 3,000 OCT

    // Risk management caps
    const MAX_BET_AMOUNT: u64 = 10_000_000_000_000; // 10,000 OCT
    const MAX_PAYOUT_PER_BET: u64 = 100_000_000_000_000; // 100,000 OCT
    const MAX_MATCH_PAYOUTS: u64 = 500_000_000_000_000; // 500,000 OCT

    // Odds compression (1.3x - 1.7x range)
    const MIN_ODDS: u64 = 1_300_000_000_000_000_000;
    const MAX_ODDS: u64 = 1_700_000_000_000_000_000;

    const SCALE_18: u64 = 1_000_000_000_000_000_000;

    // === Error Codes ===
    const E_NOT_ADMIN: u64 = 0;
    const E_POOL_NOT_SEEDED: u64 = 2;
    const E_MATCH_NOT_SETTLED: u64 = 3;
    const E_BET_TOO_LARGE: u64 = 4;
    const E_INSUFFICIENT_PAYMENT: u64 = 5;
    const E_ALREADY_CLAIMED: u64 = 6;
    const E_NOT_BETTOR: u64 = 7;
    const E_INVALID_MATCH_COUNT: u64 = 8;
    const E_INVALID_OUTCOME: u64 = 9;
    const E_PAYOUT_CAP_REACHED: u64 = 10;
    const E_INSUFFICIENT_LIQUIDITY: u64 = 11;
    const E_MATCH_ALREADY_SEEDED: u64 = 12;
    const E_MATCH_ID_MISMATCH: u64 = 13;

    // === Structs ===

    /// Match betting pool
    public struct MatchPool has store, copy, drop {
        home_win_pool: u64,
        away_win_pool: u64,
        draw_pool: u64,
        total_pool: u64,
    }

    /// Locked odds (set at seeding, immutable)
    public struct LockedOdds has store, copy, drop {
        home_odds: u64,
        away_odds: u64,
        draw_odds: u64,
    }

    /// Prediction within a bet
    public struct Prediction has store, copy, drop {
        match_index: u64,
        predicted_outcome: u8,
        amount_in_pool: u64,
    }

    /// Per-match accounting (shared object)
    public struct MatchAccounting has key {
        id: UID,
        match_id: u64,

        pool: MatchPool,
        odds: LockedOdds,

        total_bet_volume: u64,
        total_paid_out: u64,
        protocol_fee_collected: u64,
        lp_borrowed: u64,
        seed_amount: u64,

        /// Per-match escrow (holds OCT for this match)
        escrow: Balance<OCT>,

        seeded: bool,
    }

    /// Individual bet (owned NFT)
    public struct Bet has key, store {
        id: UID,
        bet_id: u64,
        bettor: address,
        match_id: u64,
        amount: u64,
        amount_after_fee: u64,
        locked_multiplier: u64,
        predictions: vector<Prediction>,
        settled: bool,
        claimed: bool,
    }

    /// Liquidity vault (persistent shared object)
    public struct LiquidityVault has key {
        id: UID,
        balance: Balance<OCT>,
        total_lp_shares: u64,
        lp_positions: Table<address, u64>,
        protocol_treasury: address,
        season_reward_pool: Balance<OCT>,
        admin: address,
        next_bet_id: u64,
        /// Track which match_ids have been seeded (prevents duplicates)
        seeded_matches: Table<u64, bool>,
    }

    /// LP position token (non-transferable, key only)
    public struct LPToken has key {
        id: UID,
        shares: u64,
    }

    // === Events ===

    public struct MatchPoolSeeded has copy, drop {
        match_id: u64,
        seed_amount: u64,
        timestamp: u64,
    }

    public struct BetPlaced has copy, drop {
        bet_id: u64,
        bettor: address,
        match_id: u64,
        amount: u64,
        parlay_multiplier: u64,
        num_matches: u64,
    }

    public struct WinningsClaimed has copy, drop {
        bet_id: u64,
        bettor: address,
        base_payout: u64,
        final_payout: u64,
        parlay_multiplier: u64,
    }

    public struct BetLost has copy, drop {
        bet_id: u64,
        bettor: address,
    }

    public struct MatchRevenueFinal has copy, drop {
        match_id: u64,
        profit_to_lp: u64,
        loss_from_lp: u64,
        season_share: u64,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let vault = LiquidityVault {
            id: object::new(ctx),
            balance: balance::zero<OCT>(),
            total_lp_shares: 0,
            lp_positions: table::new(ctx),
            protocol_treasury: tx_context::sender(ctx),
            season_reward_pool: balance::zero<OCT>(),
            admin: tx_context::sender(ctx),
            next_bet_id: 1,
            seeded_matches: table::new(ctx),
        };
        transfer::share_object(vault);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Liquidity Management ===

    /// Add liquidity to vault and receive LP shares
    public entry fun add_liquidity(
        vault: &mut LiquidityVault,
        payment: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&payment);
        assert!(amount > 0, E_INSUFFICIENT_PAYMENT);

        let shares = if (vault.total_lp_shares == 0) {
            amount
        } else {
            let vault_balance = balance::value(&vault.balance);
            if (vault_balance == 0) {
                amount
            } else {
                (amount * vault.total_lp_shares) / vault_balance
            }
        };

        balance::join(&mut vault.balance, coin::into_balance(payment));
        vault.total_lp_shares = vault.total_lp_shares + shares;

        let sender = tx_context::sender(ctx);
        if (table::contains(&vault.lp_positions, sender)) {
            let existing = table::borrow_mut(&mut vault.lp_positions, sender);
            *existing = *existing + shares;
        } else {
            table::add(&mut vault.lp_positions, sender, shares);
        };

        let lp_token = LPToken {
            id: object::new(ctx),
            shares,
        };
        transfer::transfer(lp_token, sender);
    }

    /// Remove liquidity by burning LP token
    /// LP token is non-transferable, so only the original depositor can withdraw
    public entry fun remove_liquidity(
        vault: &mut LiquidityVault,
        lp_token: LPToken,
        ctx: &mut TxContext
    ) {
        let LPToken { id, shares } = lp_token;
        object::delete(id);

        let sender = tx_context::sender(ctx);
        assert!(shares > 0, E_INSUFFICIENT_PAYMENT);

        let vault_balance = balance::value(&vault.balance);
        assert!(vault.total_lp_shares > 0, E_INSUFFICIENT_LIQUIDITY);
        let withdrawal = (shares * vault_balance) / vault.total_lp_shares;

        vault.total_lp_shares = vault.total_lp_shares - shares;

        if (table::contains(&vault.lp_positions, sender)) {
            let pos = table::borrow_mut(&mut vault.lp_positions, sender);
            assert!(*pos >= shares, E_INSUFFICIENT_LIQUIDITY);
            *pos = *pos - shares;
            if (*pos == 0) {
                table::remove(&mut vault.lp_positions, sender);
            };
        };

        let withdrawal_coin = coin::from_balance(
            balance::split(&mut vault.balance, withdrawal),
            ctx
        );
        transfer::public_transfer(withdrawal_coin, sender);
    }

    // === Seeding Functions ===

    /// Seed match pool with differentiated odds based on team matchup
    /// Actually reserves SEED_PER_MATCH from vault into per-match escrow
    public entry fun seed_match(
        vault: &mut LiquidityVault,
        match_data: &MatchData,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, E_NOT_ADMIN);
        assert!(balance::value(&vault.balance) >= SEED_PER_MATCH, E_INSUFFICIENT_LIQUIDITY);

        let match_id = game_engine::get_match_id(match_data);

        // Prevent duplicate seeding (Fix #8)
        assert!(!table::contains(&vault.seeded_matches, match_id), E_MATCH_ALREADY_SEEDED);
        table::add(&mut vault.seeded_matches, match_id, true);

        let (home_seed, away_seed, draw_seed) = calculate_match_seeds(match_id);

        let total = home_seed + away_seed + draw_seed;

        // Calculate raw odds then compress
        let raw_home_odds = (total * SCALE_18) / home_seed;
        let raw_away_odds = (total * SCALE_18) / away_seed;
        let raw_draw_odds = (total * SCALE_18) / draw_seed;

        // Actually move seed funds from vault to match escrow (Fix #1)
        let escrow = balance::split(&mut vault.balance, SEED_PER_MATCH);

        let accounting = MatchAccounting {
            id: object::new(ctx),
            match_id,
            pool: MatchPool {
                home_win_pool: home_seed,
                away_win_pool: away_seed,
                draw_pool: draw_seed,
                total_pool: total,
            },
            odds: LockedOdds {
                home_odds: compress_odds(raw_home_odds),
                away_odds: compress_odds(raw_away_odds),
                draw_odds: compress_odds(raw_draw_odds),
            },
            total_bet_volume: 0,
            total_paid_out: 0,
            protocol_fee_collected: 0,
            lp_borrowed: 0,
            seed_amount: SEED_PER_MATCH,
            escrow,
            seeded: true,
        };

        transfer::share_object(accounting);

        event::emit(MatchPoolSeeded {
            match_id,
            seed_amount: SEED_PER_MATCH,
            timestamp: 0,
        });
    }

    /// Calculate differentiated seeds for a match using deterministic hashing
    fun calculate_match_seeds(match_id: u64): (u64, u64, u64) {
        let hash_bytes = std::bcs::to_bytes(&match_id);
        let hash = std::hash::sha3_256(hash_bytes);

        let home_strength = (*vector::borrow(&hash, 0) as u64) % 100;
        let away_strength = (*vector::borrow(&hash, 1) as u64) % 100;

        let diff = if (home_strength > away_strength) {
            home_strength - away_strength
        } else {
            away_strength - home_strength
        };

        let (favorite_alloc, underdog_alloc, draw_alloc) = if (diff > 65) {
            (50, 18, 32)
        } else if (diff > 50) {
            (46, 23, 31)
        } else if (diff > 35) {
            (42, 27, 31)
        } else if (diff > 20) {
            (38, 31, 31)
        } else if (diff > 8) {
            (36, 33, 31)
        } else {
            (34, 34, 32)
        };

        let (home_seed, away_seed) = if (home_strength > away_strength) {
            ((SEED_PER_MATCH * favorite_alloc) / 100, (SEED_PER_MATCH * underdog_alloc) / 100)
        } else {
            ((SEED_PER_MATCH * underdog_alloc) / 100, (SEED_PER_MATCH * favorite_alloc) / 100)
        };

        let draw_seed = (SEED_PER_MATCH * draw_alloc) / 100;
        (home_seed, away_seed, draw_seed)
    }

    /// Compress raw parimutuel odds to 1.3x-1.7x range
    fun compress_odds(raw_odds: u64): u64 {
        if (raw_odds < 1_800_000_000_000_000_000) {
            MIN_ODDS
        } else if (raw_odds > 5_500_000_000_000_000_000) {
            MAX_ODDS
        } else {
            let excess = raw_odds - 1_800_000_000_000_000_000;
            let scaled_excess = (excess * 108) / 1000;
            MIN_ODDS + scaled_excess
        }
    }

    // === Betting Functions ===

    /// Place a single-outcome bet on a match
    public entry fun place_bet(
        accounting: &mut MatchAccounting,
        vault: &mut LiquidityVault,
        outcome: u8, // 1=home, 2=away, 3=draw
        mut payment: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        assert!(accounting.seeded, E_POOL_NOT_SEEDED);
        assert!(outcome >= 1 && outcome <= 3, E_INVALID_OUTCOME);

        let amount = coin::value(&payment);
        assert!(amount > 0 && amount <= MAX_BET_AMOUNT, E_BET_TOO_LARGE);

        // Deduct 5% protocol fee
        let fee = (amount * PROTOCOL_FEE_BPS) / 10000;
        let fee_coin = coin::split(&mut payment, fee, ctx);
        transfer::public_transfer(fee_coin, vault.protocol_treasury);

        let amount_after_fee = amount - fee;
        accounting.protocol_fee_collected = accounting.protocol_fee_collected + fee;

        // Add bet amount to pool outcome bucket
        if (outcome == 1) {
            accounting.pool.home_win_pool = accounting.pool.home_win_pool + amount_after_fee;
        } else if (outcome == 2) {
            accounting.pool.away_win_pool = accounting.pool.away_win_pool + amount_after_fee;
        } else {
            accounting.pool.draw_pool = accounting.pool.draw_pool + amount_after_fee;
        };
        accounting.pool.total_pool = accounting.pool.total_pool + amount_after_fee;

        // Deposit bet funds into match escrow (Fix #1 - funds are match-specific)
        balance::join(&mut accounting.escrow, coin::into_balance(payment));

        accounting.total_bet_volume = accounting.total_bet_volume + amount_after_fee;

        // Assign bet ID
        let bet_id = vault.next_bet_id;
        vault.next_bet_id = bet_id + 1;

        // Create single-prediction bet
        let mut predictions = vector::empty<Prediction>();
        vector::push_back(&mut predictions, Prediction {
            match_index: accounting.match_id,
            predicted_outcome: outcome,
            amount_in_pool: amount_after_fee,
        });

        let bet = Bet {
            id: object::new(ctx),
            bet_id,
            bettor: tx_context::sender(ctx),
            match_id: accounting.match_id,
            amount,
            amount_after_fee,
            locked_multiplier: SCALE_18, // 1.0x for single bet
            predictions,
            settled: false,
            claimed: false,
        };

        event::emit(BetPlaced {
            bet_id,
            bettor: tx_context::sender(ctx),
            match_id: accounting.match_id,
            amount,
            parlay_multiplier: SCALE_18,
            num_matches: 1,
        });

        transfer::public_transfer(bet, tx_context::sender(ctx));
    }

    fun get_odds_for_outcome(odds: &LockedOdds, outcome: u8): u64 {
        if (outcome == 1) { odds.home_odds }
        else if (outcome == 2) { odds.away_odds }
        else { odds.draw_odds }
    }

    // === Claim Winnings ===

    /// Claim winnings for a bet after match settlement
    public entry fun claim_winnings(
        bet: &mut Bet,
        accounting: &mut MatchAccounting,
        match_data: &MatchData,
        ctx: &mut TxContext
    ) {
        assert!(game_engine::is_match_settled(match_data), E_MATCH_NOT_SETTLED);
        assert!(!bet.claimed, E_ALREADY_CLAIMED);
        assert!(bet.bettor == tx_context::sender(ctx), E_NOT_BETTOR);

        // Fix #4: Assert match_id alignment
        assert!(game_engine::get_match_id(match_data) == accounting.match_id, E_MATCH_ID_MISMATCH);
        assert!(bet.match_id == accounting.match_id, E_MATCH_ID_MISMATCH);

        let (won, base_payout, final_payout) = calculate_payout(bet, accounting, match_data);

        bet.claimed = true;
        bet.settled = true;

        if (won && final_payout > 0) {
            assert!(accounting.total_paid_out + final_payout <= MAX_MATCH_PAYOUTS, E_PAYOUT_CAP_REACHED);
            // Pay from match escrow (Fix #1)
            assert!(balance::value(&accounting.escrow) >= final_payout, E_INSUFFICIENT_LIQUIDITY);

            accounting.total_paid_out = accounting.total_paid_out + final_payout;

            let payout_coin = coin::from_balance(
                balance::split(&mut accounting.escrow, final_payout),
                ctx
            );
            transfer::public_transfer(payout_coin, bet.bettor);

            event::emit(WinningsClaimed {
                bet_id: bet.bet_id,
                bettor: bet.bettor,
                base_payout,
                final_payout,
                parlay_multiplier: bet.locked_multiplier,
            });
        } else {
            event::emit(BetLost {
                bet_id: bet.bet_id,
                bettor: bet.bettor,
            });
        };
    }

    /// Calculate bet payout using locked odds and multiplier
    fun calculate_payout(
        bet: &Bet,
        accounting: &MatchAccounting,
        match_data: &MatchData
    ): (bool, u64, u64) {
        let mut all_correct = true;
        let mut total_base_payout = 0;
        let match_outcome = game_engine::get_match_outcome(match_data);

        let mut i = 0;
        while (i < vector::length(&bet.predictions)) {
            let pred = vector::borrow(&bet.predictions, i);

            if (match_outcome != pred.predicted_outcome) {
                all_correct = false;
                break
            };

            let locked_odds = get_odds_for_outcome(&accounting.odds, pred.predicted_outcome);
            let match_payout = (pred.amount_in_pool * locked_odds) / SCALE_18;
            total_base_payout = total_base_payout + match_payout;

            i = i + 1;
        };

        if (!all_correct) {
            return (false, 0, 0)
        };

        let mut final_payout = (total_base_payout * bet.locked_multiplier) / SCALE_18;

        if (final_payout > MAX_PAYOUT_PER_BET) {
            final_payout = MAX_PAYOUT_PER_BET;
        };

        (true, total_base_payout, final_payout)
    }

    // === Team-Based Seeding (AI Football Manager) ===

    /// Seed match pool from team stats (AI-calculated odds)
    /// Actually reserves SEED_PER_MATCH from vault into per-match escrow
    public entry fun seed_team_match(
        vault: &mut LiquidityVault,
        scheduled: &ScheduledMatch,
        home_team: &TeamNFT,
        away_team: &TeamNFT,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, E_NOT_ADMIN);
        assert!(balance::value(&vault.balance) >= SEED_PER_MATCH, E_INSUFFICIENT_LIQUIDITY);

        let match_id = ai_match_engine::get_match_id(scheduled);

        // Prevent duplicate seeding (Fix #8)
        assert!(!table::contains(&vault.seeded_matches, match_id), E_MATCH_ALREADY_SEEDED);
        table::add(&mut vault.seeded_matches, match_id, true);

        // Calculate odds from team stats
        let (home_seed, away_seed, draw_seed) = calculate_team_seeds(home_team, away_team);
        let total = home_seed + away_seed + draw_seed;

        // Calculate raw odds then compress
        let raw_home_odds = (total * SCALE_18) / home_seed;
        let raw_away_odds = (total * SCALE_18) / away_seed;
        let raw_draw_odds = (total * SCALE_18) / draw_seed;

        // Actually move seed funds from vault to match escrow (Fix #1)
        let escrow = balance::split(&mut vault.balance, SEED_PER_MATCH);

        let accounting = MatchAccounting {
            id: object::new(ctx),
            match_id,
            pool: MatchPool {
                home_win_pool: home_seed,
                away_win_pool: away_seed,
                draw_pool: draw_seed,
                total_pool: total,
            },
            odds: LockedOdds {
                home_odds: compress_odds(raw_home_odds),
                away_odds: compress_odds(raw_away_odds),
                draw_odds: compress_odds(raw_draw_odds),
            },
            total_bet_volume: 0,
            total_paid_out: 0,
            protocol_fee_collected: 0,
            lp_borrowed: 0,
            seed_amount: SEED_PER_MATCH,
            escrow,
            seeded: true,
        };

        transfer::share_object(accounting);

        event::emit(MatchPoolSeeded {
            match_id,
            seed_amount: SEED_PER_MATCH,
            timestamp: 0,
        });
    }

    /// Calculate seed allocations from team stats
    fun calculate_team_seeds(home_team: &TeamNFT, away_team: &TeamNFT): (u64, u64, u64) {
        let home_strength = team_nft::get_team_strength(home_team);
        let away_strength = team_nft::get_team_strength(away_team);

        // Home advantage (+5)
        let home_adj = home_strength + 5;
        let total_strength = home_adj + away_strength;

        // Convert strength to seed allocation percentages
        // Stronger team = more seed (lower odds, more likely to win)
        let home_pct = (home_adj * 100) / total_strength;

        // Draw gets ~25% of total pool
        let draw_pct = 25;
        let remaining = 100 - draw_pct;
        let home_final_pct = (home_pct * remaining) / 100;
        let away_final_pct = remaining - home_final_pct;

        let home_seed = (SEED_PER_MATCH * home_final_pct) / 100;
        let away_seed = (SEED_PER_MATCH * away_final_pct) / 100;
        let draw_seed = (SEED_PER_MATCH * draw_pct) / 100;

        (home_seed, away_seed, draw_seed)
    }

    /// Claim winnings using match engine result (for team matches)
    public entry fun claim_team_winnings(
        bet: &mut Bet,
        accounting: &mut MatchAccounting,
        scheduled: &ScheduledMatch,
        ctx: &mut TxContext
    ) {
        assert!(ai_match_engine::is_match_settled(scheduled), E_MATCH_NOT_SETTLED);
        assert!(!bet.claimed, E_ALREADY_CLAIMED);
        assert!(bet.bettor == tx_context::sender(ctx), E_NOT_BETTOR);

        // Fix #4: Assert match_id alignment
        assert!(ai_match_engine::get_match_id(scheduled) == accounting.match_id, E_MATCH_ID_MISMATCH);
        assert!(bet.match_id == accounting.match_id, E_MATCH_ID_MISMATCH);

        // Get match outcome from scheduled match
        let match_outcome = ai_match_engine::get_match_outcome(scheduled);

        let (won, base_payout, final_payout) = calculate_payout_from_outcome(bet, accounting, match_outcome);

        bet.claimed = true;
        bet.settled = true;

        if (won && final_payout > 0) {
            assert!(accounting.total_paid_out + final_payout <= MAX_MATCH_PAYOUTS, E_PAYOUT_CAP_REACHED);
            // Pay from match escrow (Fix #1)
            assert!(balance::value(&accounting.escrow) >= final_payout, E_INSUFFICIENT_LIQUIDITY);

            accounting.total_paid_out = accounting.total_paid_out + final_payout;

            let payout_coin = coin::from_balance(
                balance::split(&mut accounting.escrow, final_payout),
                ctx
            );
            transfer::public_transfer(payout_coin, bet.bettor);

            event::emit(WinningsClaimed {
                bet_id: bet.bet_id,
                bettor: bet.bettor,
                base_payout,
                final_payout,
                parlay_multiplier: bet.locked_multiplier,
            });
        } else {
            event::emit(BetLost {
                bet_id: bet.bet_id,
                bettor: bet.bettor,
            });
        };
    }

    /// Calculate payout from raw outcome (1=home, 2=away, 3=draw)
    fun calculate_payout_from_outcome(
        bet: &Bet,
        accounting: &MatchAccounting,
        match_outcome: u8
    ): (bool, u64, u64) {
        let mut all_correct = true;
        let mut total_base_payout = 0;

        let mut i = 0;
        while (i < vector::length(&bet.predictions)) {
            let pred = vector::borrow(&bet.predictions, i);

            if (match_outcome != pred.predicted_outcome) {
                all_correct = false;
                break
            };

            let locked_odds = get_odds_for_outcome(&accounting.odds, pred.predicted_outcome);
            let match_payout = (pred.amount_in_pool * locked_odds) / SCALE_18;
            total_base_payout = total_base_payout + match_payout;

            i = i + 1;
        };

        if (!all_correct) {
            return (false, 0, 0)
        };

        let mut final_payout = (total_base_payout * bet.locked_multiplier) / SCALE_18;

        if (final_payout > MAX_PAYOUT_PER_BET) {
            final_payout = MAX_PAYOUT_PER_BET;
        };

        (true, total_base_payout, final_payout)
    }

    // === Settlement ===

    /// Finalize match revenue: return escrow to vault, deposit season share
    /// Moves real OCT between accounts (Fix #2)
    public entry fun finalize_match_revenue(
        accounting: &mut MatchAccounting,
        vault: &mut LiquidityVault,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, E_NOT_ADMIN);

        let season_share = (accounting.total_bet_volume * SEASON_POOL_SHARE_BPS) / 10000;
        let escrow_remaining = balance::value(&accounting.escrow);

        // Move season share from escrow to season reward pool
        if (season_share > 0 && escrow_remaining >= season_share) {
            let season_coin = balance::split(&mut accounting.escrow, season_share);
            balance::join(&mut vault.season_reward_pool, season_coin);
        };

        // Return remaining escrow to vault (LP profit or remaining balance)
        let remaining = balance::value(&accounting.escrow);
        if (remaining > 0) {
            balance::join(&mut vault.balance, balance::withdraw_all(&mut accounting.escrow));
        };

        let total_in_contract = accounting.total_bet_volume + accounting.seed_amount;
        let (profit_to_lp, loss_from_lp) = if (accounting.total_paid_out > total_in_contract) {
            (0, accounting.total_paid_out - total_in_contract)
        } else {
            (total_in_contract - accounting.total_paid_out - season_share, 0)
        };

        event::emit(MatchRevenueFinal {
            match_id: accounting.match_id,
            profit_to_lp,
            loss_from_lp,
            season_share,
        });
    }

    // === Admin Functions ===

    /// Withdraw protocol fees (admin only)
    /// Note: Protocol fees are sent directly to protocol_treasury address during place_bet.
    /// This function withdraws from the season_reward_pool (collected from finalize_match_revenue).
    public entry fun withdraw_protocol_fees(
        vault: &mut LiquidityVault,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, E_NOT_ADMIN);
        let amount = balance::value(&vault.season_reward_pool);
        assert!(amount > 0, E_INSUFFICIENT_LIQUIDITY);
        let coin_out = coin::from_balance(
            balance::withdraw_all(&mut vault.season_reward_pool),
            ctx
        );
        transfer::public_transfer(coin_out, vault.admin);
    }

    /// Withdraw season reward pool (admin only)
    public entry fun withdraw_season_pool(
        vault: &mut LiquidityVault,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, E_NOT_ADMIN);
        let amount = balance::value(&vault.season_reward_pool);
        if (amount > 0) {
            let coin_out = coin::from_balance(
                balance::withdraw_all(&mut vault.season_reward_pool),
                ctx
            );
            transfer::public_transfer(coin_out, vault.admin);
        };
    }

    // === View Functions ===

    public fun get_locked_odds(accounting: &MatchAccounting): &LockedOdds {
        &accounting.odds
    }

    public fun get_match_pool(accounting: &MatchAccounting): &MatchPool {
        &accounting.pool
    }

    public fun is_match_seeded(accounting: &MatchAccounting): bool {
        accounting.seeded
    }

    public fun get_match_id(accounting: &MatchAccounting): u64 {
        accounting.match_id
    }

    public fun get_protocol_fee_collected(accounting: &MatchAccounting): u64 {
        accounting.protocol_fee_collected
    }

    public fun get_total_bet_volume(accounting: &MatchAccounting): u64 {
        accounting.total_bet_volume
    }

    public fun get_escrow_balance(accounting: &MatchAccounting): u64 {
        balance::value(&accounting.escrow)
    }
}
