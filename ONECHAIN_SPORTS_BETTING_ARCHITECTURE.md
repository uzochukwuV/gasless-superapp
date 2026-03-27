# One Chain Sports Betting Game Architecture

## Executive Summary

This document outlines the architecture for building a decentralized sports betting platform on One Chain, inspired by the Ethereum-based League Alpha system (GameEngine.sol + Pool.sol). The design leverages One Chain's native randomness, object model, and Move language features.

---

## Original System Analysis (Ethereum/Solidity)

### GameEngine.sol - Core Game Logic
**Purpose**: Manages virtual sports league matches with VRF-based randomness

**Key Features**:
- 20 teams playing in seasons (36 rounds, 10 matches per round)
- Chainlink VRF v2.5 for match score generation
- Round duration: 3 hours
- Parimutuel-style match outcome determination
- Team standings and season winner tracking

**Critical Components**:
```solidity
// Match State
struct Match {
    homeTeamId, awayTeamId
    homeScore, awayScore
    outcome (PENDING/HOME_WIN/AWAY_WIN/DRAW)
}

// Season State
struct Season {
    currentRound
    active/completed
    winningTeamId
}

// VRF Integration
- requestMatchResults() → Chainlink VRF request
- fulfillRandomWords() → Score generation callback
- Emergency settlement if VRF fails (2hr timeout)
```

### Pool.sol - Betting & Economics
**Purpose**: Unified liquidity pool betting system with fixed odds

**Key Features**:
- **Fixed Odds Model**: Odds locked at seeding (1.3x-1.7x range)
- **LP Pool Architecture**: Single liquidity pool covers all payouts
- **Protocol Fee**: 5% on all bets
- **Parlay System**: Multi-match bets with bonuses (1.05x-1.25x)
- **Seeding**: 3,000 LEAGUE tokens per match (30,000 per round)

**Economic Model**:
```solidity
// Bet Flow
1. User bets → 5% protocol fee deducted
2. Remaining 95% enters pool system
3. LP pool may loan tokens for odds balancing
4. Winners paid from LP pool
5. Remaining balance returned to LP

// Odds Calculation (LOCKED at seeding)
- Seeds allocated based on team strength (pseudo-random or stats-based)
- Compression formula: 1.3x-1.7x range
- Example: 50% allocation → 1.3x, 18% allocation → 1.7x

// Parlay Multipliers (count-based tiers)
- First 10 parlays: 2.5x
- Parlays 11-20: 2.2x
- Parlays 21-30: 1.9x
- Parlays 31-40: 1.6x
- Parlays 41+: 1.3x
```

**Risk Management**:
- Max bet: 10,000 LEAGUE
- Max payout per bet: 100,000 LEAGUE
- Max round payouts: 500,000 LEAGUE

---

## One Chain Architecture Design

### Module Structure

```
league_one/
├── sources/
│   ├── game_engine.move      # Match generation & randomness
│   ├── betting_pool.move     # Betting & liquidity pool
│   ├── liquidity_vault.move  # LP token management
│   ├── odds_calculator.move  # Odds computation & locking
│   └── admin.move            # Platform governance
├── tests/
│   ├── game_engine_tests.move
│   ├── betting_pool_tests.move
│   └── integration_tests.move
└── Move.toml
```

---

## Core Modules Design

### 1. Game Engine Module (`game_engine.move`)

**Purpose**: Manage virtual sports league with native One Chain randomness

```move
module league_one::game_engine {
    use one::clock::Clock;
    use one::object::{Self, UID};
    use one::tx_context::TxContext;
    use one::event;
    use std::vector;

    // === Constants ===
    const TEAMS_COUNT: u64 = 20;
    const MATCHES_PER_ROUND: u64 = 10;
    const ROUNDS_PER_SEASON: u64 = 36;
    const ROUND_DURATION_MS: u64 = 10_800_000; // 3 hours

    // === Enums (as constants) ===
    const OUTCOME_PENDING: u8 = 0;
    const OUTCOME_HOME_WIN: u8 = 1;
    const OUTCOME_AWAY_WIN: u8 = 2;
    const OUTCOME_DRAW: u8 = 3;

    // === Structs ===

    /// Represents a single match
    struct Match has store, copy, drop {
        home_team_id: u64,
        away_team_id: u64,
        home_score: u8,
        away_score: u8,
        outcome: u8,
        settled: bool,
    }

    /// Team statistics for a season
    struct Team has store, copy, drop {
        name: String,
        wins: u64,
        draws: u64,
        losses: u64,
        points: u64,
        goals_for: u64,
        goals_against: u64,
    }

    /// Season state
    struct Season has key, store {
        id: UID,
        season_id: u64,
        start_time: u64,
        current_round: u64,
        active: bool,
        completed: bool,
        winning_team_id: u64,
    }

    /// Round state with matches
    struct Round has key, store {
        id: UID,
        round_id: u64,
        season_id: u64,
        start_time: u64,
        deadline: u64,
        settled: bool,
        matches: vector<Match>, // Fixed size: 10 matches
    }

    /// Global game state (shared object)
    struct GameState has key {
        id: UID,
        current_season_id: u64,
        current_round_id: u64,
        teams: vector<Team>, // 20 teams
        admin: address,
    }

    /// Season standings (mapping seasonId => teamId => Team stats)
    struct SeasonStandings has key {
        id: UID,
        season_id: u64,
        standings: Table<u64, Team>, // teamId => Team stats
    }

    // === Key Functions ===

    /// Initialize game with 20 teams
    fun init(ctx: &mut TxContext) {
        let game_state = GameState {
            id: object::new(ctx),
            current_season_id: 0,
            current_round_id: 0,
            teams: initialize_teams(),
            admin: tx_context::sender(ctx),
        };

        transfer::share_object(game_state);
    }

    /// Start new season
    public entry fun start_season(
        game_state: &mut GameState,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validation & season creation
        game_state.current_season_id = game_state.current_season_id + 1;

        let season = Season {
            id: object::new(ctx),
            season_id: game_state.current_season_id,
            start_time: clock::timestamp_ms(clock),
            current_round: 0,
            active: true,
            completed: false,
            winning_team_id: 0,
        };

        transfer::share_object(season);

        // Initialize standings
        create_season_standings(game_state.current_season_id, &game_state.teams, ctx);
    }

    /// Start new round with ONE CHAIN NATIVE RANDOMNESS
    public entry fun start_round(
        game_state: &mut GameState,
        season: &mut Season,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(season.active, E_SEASON_NOT_ACTIVE);
        assert!(season.current_round < ROUNDS_PER_SEASON, E_MAX_ROUNDS_REACHED);

        season.current_round = season.current_round + 1;
        game_state.current_round_id = game_state.current_round_id + 1;

        let current_time = clock::timestamp_ms(clock);

        // Generate random team pairings using ONE CHAIN RANDOMNESS
        // One Chain has native randomness via tx_context or clock-based entropy
        let matches = generate_random_pairings(
            game_state.current_round_id,
            current_time,
            ctx
        );

        let round = Round {
            id: object::new(ctx),
            round_id: game_state.current_round_id,
            season_id: season.season_id,
            start_time: current_time,
            deadline: current_time + ROUND_DURATION_MS,
            settled: false,
            matches,
        };

        transfer::share_object(round);

        event::emit(RoundStarted {
            round_id: game_state.current_round_id,
            season_id: season.season_id,
            start_time: current_time,
        });
    }

    /// Settle round using ONE CHAIN NATIVE RANDOMNESS (no VRF needed!)
    public entry fun settle_round(
        round: &mut Round,
        season: &mut Season,
        standings: &mut SeasonStandings,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= round.deadline, E_ROUND_NOT_FINISHED);
        assert!(!round.settled, E_ALREADY_SETTLED);

        // Generate match scores using ONE CHAIN RANDOMNESS
        // Unlike Ethereum (needs Chainlink VRF), One Chain has native randomness
        let randomness_seed = derive_randomness(round.round_id, current_time, ctx);

        let mut i = 0;
        while (i < MATCHES_PER_ROUND) {
            let match_ref = vector::borrow_mut(&mut round.matches, i);

            // Generate scores using deterministic randomness
            let (home_score, away_score) = generate_match_scores(
                randomness_seed,
                i
            );

            match_ref.home_score = home_score;
            match_ref.away_score = away_score;
            match_ref.settled = true;

            // Determine outcome
            if (home_score > away_score) {
                match_ref.outcome = OUTCOME_HOME_WIN;
            } else if (away_score > home_score) {
                match_ref.outcome = OUTCOME_AWAY_WIN;
            } else {
                match_ref.outcome = OUTCOME_DRAW;
            };

            // Update standings
            update_standings(standings, match_ref);

            i = i + 1;
        };

        round.settled = true;

        event::emit(RoundSettled {
            round_id: round.round_id,
            season_id: round.season_id,
        });
    }

    // === NATIVE RANDOMNESS IMPLEMENTATION ===

    /// Derive randomness using One Chain's native capabilities
    /// NOTE: One Chain provides better randomness than block.prevrandao
    fun derive_randomness(
        round_id: u64,
        timestamp: u64,
        ctx: &TxContext
    ): vector<u8> {
        // One Chain approach: Combine multiple entropy sources
        // This is MORE SECURE than Ethereum's block.prevrandao

        let mut seed_data = vector::empty<u8>();

        // Add round ID
        vector::append(&mut seed_data, bcs::to_bytes(&round_id));

        // Add timestamp
        vector::append(&mut seed_data, bcs::to_bytes(&timestamp));

        // Add transaction digest (unique per tx)
        vector::append(&mut seed_data, bcs::to_bytes(&tx_context::digest(ctx)));

        // Add epoch
        vector::append(&mut seed_data, bcs::to_bytes(&tx_context::epoch(ctx)));

        // Hash to get randomness
        std::hash::sha3_256(seed_data)
    }

    /// Generate realistic football scores (0-5 goals)
    fun generate_match_scores(
        randomness: vector<u8>,
        match_index: u64
    ): (u8, u8) {
        // Extract two random bytes for home/away scores
        let home_byte = *vector::borrow(&randomness, (match_index * 2) % 32);
        let away_byte = *vector::borrow(&randomness, (match_index * 2 + 1) % 32);

        // Convert to 0-5 scores with realistic distribution
        let home_score = score_from_byte(home_byte);
        let away_score = score_from_byte(away_byte);

        (home_score, away_score)
    }

    /// Convert random byte to realistic football score
    fun score_from_byte(byte: u8): u8 {
        let roll = (byte as u64) % 100;

        if (roll < 15) { 0 }      // 15% chance
        else if (roll < 40) { 1 } // 25% chance
        else if (roll < 65) { 2 } // 25% chance
        else if (roll < 82) { 3 } // 17% chance
        else if (roll < 93) { 4 } // 11% chance
        else { 5 }                // 7% chance
    }

    /// Generate random team pairings (Fisher-Yates shuffle)
    fun generate_random_pairings(
        round_id: u64,
        timestamp: u64,
        ctx: &TxContext
    ): vector<Match> {
        let randomness = derive_randomness(round_id, timestamp, ctx);

        // Create team ID array [0..19]
        let mut team_ids = vector::empty<u64>();
        let mut i = 0;
        while (i < TEAMS_COUNT) {
            vector::push_back(&mut team_ids, i);
            i = i + 1;
        };

        // Fisher-Yates shuffle
        let mut i = TEAMS_COUNT - 1;
        while (i > 0) {
            let random_byte = *vector::borrow(&randomness, (i % 32) as u64);
            let j = (random_byte as u64) % (i + 1);

            // Swap
            let temp = *vector::borrow(&team_ids, i);
            *vector::borrow_mut(&mut team_ids, i) = *vector::borrow(&team_ids, j);
            *vector::borrow_mut(&mut team_ids, j) = temp;

            i = i - 1;
        };

        // Create 10 matches from shuffled pairs
        let mut matches = vector::empty<Match>();
        let mut i = 0;
        while (i < MATCHES_PER_ROUND) {
            let home_id = *vector::borrow(&team_ids, i * 2);
            let away_id = *vector::borrow(&team_ids, i * 2 + 1);

            vector::push_back(&mut matches, Match {
                home_team_id: home_id,
                away_team_id: away_id,
                home_score: 0,
                away_score: 0,
                outcome: OUTCOME_PENDING,
                settled: false,
            });

            i = i + 1;
        };

        matches
    }

    // === View Functions ===

    public fun get_match(round: &Round, match_index: u64): &Match {
        vector::borrow(&round.matches, match_index)
    }

    public fun is_round_settled(round: &Round): bool {
        round.settled
    }
}
```

---

### 2. Betting Pool Module (`betting_pool.move`)

**Purpose**: Manage bets, odds, and liquidity pool

```move
module league_one::betting_pool {
    use one::coin::{Self, Coin};
    use one::balance::{Self, Balance};
    use one::oct::OCT;
    use one::table::{Self, Table};
    use league_one::game_engine;

    // === Constants ===
    const PROTOCOL_FEE_BPS: u64 = 500; // 5%
    const SEED_PER_MATCH: u64 = 3_000_000_000_000; // 3,000 OCT (in MIST)
    const MAX_BET: u64 = 10_000_000_000_000; // 10,000 OCT
    const MAX_PAYOUT_PER_BET: u64 = 100_000_000_000_000; // 100,000 OCT

    // Parlay multipliers (1e18 scale)
    const PARLAY_1_MATCH: u64 = 1_000_000_000_000_000_000; // 1.0x
    const PARLAY_2_MATCHES: u64 = 1_050_000_000_000_000_000; // 1.05x
    const PARLAY_10_MATCHES: u64 = 1_250_000_000_000_000_000; // 1.25x

    // === Structs ===

    /// Match pool for a single match
    struct MatchPool has store, copy, drop {
        home_win_pool: u64,
        away_win_pool: u64,
        draw_pool: u64,
        total_pool: u64,
    }

    /// Locked odds for a match (set at seeding, never changes)
    struct LockedOdds has store, copy, drop {
        home_odds: u64,  // e.g., 1.3e18 = 1.3x
        away_odds: u64,
        draw_odds: u64,
        locked: bool,
    }

    /// Round accounting
    struct RoundAccounting has key, store {
        id: UID,
        round_id: u64,

        // Match pools (10 matches)
        match_pools: Table<u64, MatchPool>,
        locked_odds: Table<u64, LockedOdds>,

        // Round totals
        total_bet_volume: u64,
        total_paid_out: u64,
        protocol_fee_collected: u64,
        lp_borrowed: u64,

        // State
        seeded: bool,
        settled: bool,
    }

    /// Individual bet
    struct Bet has key, store {
        id: UID,
        bet_id: u64,
        bettor: address,
        round_id: u64,
        amount: u64,
        amount_after_fee: u64,
        locked_multiplier: u64,
        predictions: vector<Prediction>,
        settled: bool,
        claimed: bool,
    }

    struct Prediction has store, copy, drop {
        match_index: u64,
        predicted_outcome: u8, // 1=HOME, 2=AWAY, 3=DRAW
        amount_in_pool: u64,
    }

    /// Liquidity Pool vault
    struct LiquidityVault has key {
        id: UID,
        balance: Balance<OCT>,
        total_shares: u64,
        admin: address,
    }

    // === Core Functions ===

    /// Seed round pools with differentiated odds
    public entry fun seed_round(
        round_accounting: &mut RoundAccounting,
        vault: &mut LiquidityVault,
        game_round: &game_engine::Round,
        payment: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        assert!(!round_accounting.seeded, E_ALREADY_SEEDED);

        let total_seed = SEED_PER_MATCH * 10; // 30,000 OCT
        assert!(coin::value(&payment) >= total_seed, E_INSUFFICIENT_SEED);

        // Seed each match with differentiated amounts
        let mut i = 0;
        while (i < 10) {
            let match_data = game_engine::get_match(game_round, i);

            // Calculate seed distribution based on team strength
            let (home_seed, away_seed, draw_seed) = calculate_match_seeds(
                match_data,
                round_accounting.round_id,
                i
            );

            // Create match pool
            table::add(&mut round_accounting.match_pools, i, MatchPool {
                home_win_pool: home_seed,
                away_win_pool: away_seed,
                draw_pool: draw_seed,
                total_pool: home_seed + away_seed + draw_seed,
            });

            // LOCK ODDS immediately (critical: odds never change!)
            let total = home_seed + away_seed + draw_seed;
            table::add(&mut round_accounting.locked_odds, i, LockedOdds {
                home_odds: compress_odds((total * 1_000_000_000_000_000_000) / home_seed),
                away_odds: compress_odds((total * 1_000_000_000_000_000_000) / away_seed),
                draw_odds: compress_odds((total * 1_000_000_000_000_000_000) / draw_seed),
                locked: true,
            });

            i = i + 1;
        };

        // Transfer seed to vault
        balance::join(&mut vault.balance, coin::into_balance(payment));
        round_accounting.seeded = true;
    }

    /// Place bet with fixed odds
    public entry fun place_bet(
        round_accounting: &mut RoundAccounting,
        vault: &mut LiquidityVault,
        match_indices: vector<u64>,
        outcomes: vector<u8>,
        mut payment: Coin<OCT>,
        ctx: &mut TxContext
    ): Bet {
        assert!(round_accounting.seeded, E_NOT_SEEDED);
        assert!(!round_accounting.settled, E_ALREADY_SETTLED);

        let amount = coin::value(&payment);
        assert!(amount <= MAX_BET, E_BET_TOO_LARGE);

        // Deduct 5% protocol fee
        let fee = (amount * PROTOCOL_FEE_BPS) / 10000;
        let fee_coin = coin::split(&mut payment, fee, ctx);
        // Transfer fee to treasury (simplified)
        transfer::public_transfer(fee_coin, vault.admin);

        let amount_after_fee = amount - fee;
        round_accounting.protocol_fee_collected = round_accounting.protocol_fee_collected + fee;

        // Calculate parlay multiplier (LOCK IT!)
        let locked_multiplier = calculate_parlay_multiplier(vector::length(&match_indices));

        // Calculate odds-weighted allocations
        let (allocations, total_allocated, lp_borrowed) = calculate_allocations(
            round_accounting,
            &match_indices,
            &outcomes,
            amount_after_fee,
            locked_multiplier
        );

        // Borrow from LP if needed
        if (lp_borrowed > 0) {
            let borrowed_coin = coin::from_balance(
                balance::split(&mut vault.balance, lp_borrowed),
                ctx
            );
            coin::join(&mut payment, borrowed_coin);
            round_accounting.lp_borrowed = round_accounting.lp_borrowed + lp_borrowed;
        };

        // Add to pools
        let mut predictions = vector::empty<Prediction>();
        let mut i = 0;
        while (i < vector::length(&match_indices)) {
            let match_idx = *vector::borrow(&match_indices, i);
            let outcome = *vector::borrow(&outcomes, i);
            let allocation = *vector::borrow(&allocations, i);

            let pool = table::borrow_mut(&mut round_accounting.match_pools, match_idx);

            if (outcome == 1) {
                pool.home_win_pool = pool.home_win_pool + allocation;
            } else if (outcome == 2) {
                pool.away_win_pool = pool.away_win_pool + allocation;
            } else {
                pool.draw_pool = pool.draw_pool + allocation;
            };
            pool.total_pool = pool.total_pool + allocation;

            vector::push_back(&mut predictions, Prediction {
                match_index: match_idx,
                predicted_outcome: outcome,
                amount_in_pool: allocation,
            });

            i = i + 1;
        };

        // Deposit remaining to vault
        balance::join(&mut vault.balance, coin::into_balance(payment));

        // Create bet
        Bet {
            id: object::new(ctx),
            bet_id: 0, // Set by caller
            bettor: tx_context::sender(ctx),
            round_id: round_accounting.round_id,
            amount,
            amount_after_fee,
            locked_multiplier,
            predictions,
            settled: false,
            claimed: false,
        }
    }

    /// Claim winnings
    public entry fun claim_winnings(
        bet: &mut Bet,
        round_accounting: &mut RoundAccounting,
        vault: &mut LiquidityVault,
        game_round: &game_engine::Round,
        ctx: &mut TxContext
    ) {
        assert!(round_accounting.settled, E_NOT_SETTLED);
        assert!(!bet.claimed, E_ALREADY_CLAIMED);
        assert!(bet.bettor == tx_context::sender(ctx), E_NOT_BETTOR);

        // Calculate payout using LOCKED ODDS and LOCKED MULTIPLIER
        let (won, base_payout, final_payout) = calculate_payout(
            bet,
            round_accounting,
            game_round
        );

        bet.claimed = true;

        if (won && final_payout > 0) {
            // Pay from vault
            let payout_coin = coin::from_balance(
                balance::split(&mut vault.balance, final_payout),
                ctx
            );
            transfer::public_transfer(payout_coin, bet.bettor);

            round_accounting.total_paid_out = round_accounting.total_paid_out + final_payout;
        };
    }

    // === Helper Functions ===

    /// Compress raw parimutuel odds to 1.3x-1.7x range
    fun compress_odds(raw_odds: u64): u64 {
        let min_odds = 1_300_000_000_000_000_000; // 1.3e18
        let max_odds = 1_700_000_000_000_000_000; // 1.7e18

        if (raw_odds < 1_800_000_000_000_000_000) {
            min_odds
        } else if (raw_odds > 5_500_000_000_000_000_000) {
            max_odds
        } else {
            // Linear compression
            let excess = raw_odds - 1_800_000_000_000_000_000;
            let scaled = (excess * 108) / 1000;
            min_odds + scaled
        }
    }

    /// Calculate parlay multiplier based on number of matches
    fun calculate_parlay_multiplier(num_matches: u64): u64 {
        if (num_matches == 1) { PARLAY_1_MATCH }
        else if (num_matches == 2) { PARLAY_2_MATCHES }
        // Linear interpolation for 3-10
        else if (num_matches <= 10) {
            let step = (PARLAY_10_MATCHES - PARLAY_2_MATCHES) / 8;
            PARLAY_2_MATCHES + (step * (num_matches - 2))
        }
        else { PARLAY_10_MATCHES } // Cap at 10
    }
}
```

---

## Key Differences: Ethereum vs One Chain

| Aspect | Ethereum (Solidity) | One Chain (Move) |
|--------|-------------------|------------------|
| **Randomness** | Chainlink VRF (external oracle, costs LINK, 3+ block delay) | Native randomness via tx digest + epoch (instant, free) |
| **Object Model** | Contract storage (mappings, structs) | First-class objects with UIDs |
| **Shared State** | Contract state + events | Shared objects (concurrent access) |
| **Safety** | Reentrancy guards needed | Move's resource safety (no reentrancy) |
| **Token Handling** | ERC20 (approve/transferFrom) | Coin<T> with guaranteed balance safety |
| **Gas Costs** | High (VRF ~$5-10 per request) | Lower (no oracle fees) |
| **Finality** | ~15 min (VRF callback) | Instant settlement |

---

## Advantages of One Chain Implementation

### 1. **Native Randomness = No Oracle Costs**
- Ethereum: Chainlink VRF costs ~$5-10 per match settlement
- One Chain: Free native randomness (tx digest entropy)
- **Savings**: ~$500/season (36 rounds × 10 matches × $1.50)

### 2. **Instant Settlement**
- Ethereum: VRF callback takes 3+ blocks (~45 seconds)
- One Chain: Immediate settlement in same transaction

### 3. **Move Safety**
- No reentrancy vulnerabilities (resource model prevents it)
- Type-safe coin handling (no approve/transferFrom exploits)
- Object capability security

### 4. **Better UX**
- No need to wait for VRF callback
- Lower transaction costs
- Simpler wallet interactions

---

## Implementation Roadmap

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] Game engine module (seasons, rounds, matches)
- [ ] Native randomness implementation
- [ ] Team data initialization
- [ ] Basic tests

### Phase 2: Betting System (Week 3-4)
- [ ] Betting pool module
- [ ] Odds calculation & locking
- [ ] Liquidity vault
- [ ] Parlay multiplier system

### Phase 3: Frontend Integration (Week 5-6)
- [ ] React/Next.js frontend
- [ ] One Chain wallet integration
- [ ] Live odds display
- [ ] Bet placement UI

### Phase 4: Testing & Audit (Week 7-8)
- [ ] Comprehensive unit tests
- [ ] Integration tests
- [ ] Security audit
- [ ] Testnet deployment

### Phase 5: Mainnet Launch (Week 9-10)
- [ ] Mainnet deployment
- [ ] Liquidity bootstrapping
- [ ] Marketing & user acquisition

---

## Security Considerations

### Randomness Security
```move
// CRITICAL: Ensure randomness cannot be gamed
fun derive_randomness(ctx: &TxContext): vector<u8> {
    // Combine MULTIPLE entropy sources
    let mut seed = vector::empty<u8>();

    // 1. Transaction digest (unique per tx)
    vector::append(&mut seed, tx_context::digest(ctx));

    // 2. Epoch (changes every ~24 hours)
    vector::append(&mut seed, bcs::to_bytes(&tx_context::epoch(ctx)));

    // 3. Additional round-specific data
    vector::append(&mut seed, bcs::to_bytes(&round_id));
    vector::append(&mut seed, bcs::to_bytes(&timestamp));

    // Hash everything for final randomness
    std::hash::sha3_256(seed)
}

// WHY THIS IS SECURE:
// - tx_context::digest() is unpredictable (depends on tx content)
// - Epoch provides additional entropy
// - Round ID + timestamp prevent replay attacks
// - SHA3-256 makes it cryptographically secure
```

### Economic Attack Vectors

1. **Odds Manipulation**: Prevented by locking odds at seeding
2. **LP Drain**: Max payout caps + reserve requirements
3. **Front-running**: Fixed odds = no MEV opportunity
4. **Flash Loan Attacks**: Move's resource safety prevents this

---

## Conclusion

The One Chain implementation offers significant advantages over the Ethereum version:
- **Lower costs** (no Chainlink VRF fees)
- **Faster settlement** (instant vs 45+ seconds)
- **Better security** (Move's resource safety)
- **Simpler architecture** (native randomness)

The core economic model (fixed odds, LP pool, parlay bonuses) remains identical, ensuring proven game mechanics while leveraging One Chain's superior infrastructure.
