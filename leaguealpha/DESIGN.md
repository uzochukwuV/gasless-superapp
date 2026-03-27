# AI Football Manager Arena — Design Document

## Overview

An on-chain football simulation where **AI-controlled team NFTs** compete in matches, **team owners** earn from betting revenue, and **spectators** bet on outcomes using fixed-odds LP-backed pools. Each team has programmable stats and strategies that affect match outcomes deterministically.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     SPECTATOR (bettor)                           │
│  • Views upcoming matches + AI predictions                       │
│  • Bets on team outcomes (fixed odds)                            │
│  • Claims winnings after match settlement                        │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                      BETTING POOL (existing)                     │
│  • LiquidityVault (LP deposits)                                  │
│  • MatchAccounting (per-match pool, locked odds)                 │
│  • Bet NFT (owned, claimable)                                    │
│  • Parlays across multiple matches                               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                    AI MATCH ENGINE (new)                         │
│  • Takes two TeamNFTs as input                                   │
│  • Reads stats + strategy + formation                            │
│  • Formation rock-paper-scissors modifier                        │
│  • Weighted probability + One Chain randomness → score           │
│  • Emits MatchResult with full stat breakdown                    │
└──────────────────┬────────────────────────┬─────────────────────┘
                   │                        │
        ┌──────────▼──────────┐  ┌─────────▼────────────┐
        │    TEAM NFT A       │  │     TEAM NFT B       │
        │                     │  │                       │
        │ • name              │  │ • name                │
        │ • attack (1-100)    │  │ • attack (1-100)     │
        │ • defense (1-100)   │  │ • defense (1-100)    │
        │ • midfield (1-100)  │  │ • midfield (1-100)   │
        │ • formation         │  │ • formation           │
        │ • wins/loss/draws   │  │ • wins/loss/draws    │
        │ • goals_for/against │  │ • goals_for/against  │
        │ • owner address     │  │ • owner address      │
        │ • strategy style    │  │ • strategy style     │
        └──────────┬──────────┘  └─────────┬────────────┘
                   │                        │
        ┌──────────▼────────────────────────▼────────────┐
        │                TEAM OWNER                       │
        │  • Earns % of betting pool revenue              │
        │  • Pays to upgrade stats (OCT → stat boost)    │
        │  • Chooses formation + strategy                 │
        │  • Can trade team NFT on market                 │
        └─────────────────────────────────────────────────┘
```

---

## Module 1: `team_nft.move` (NEW)

### Purpose
Manages team creation, stats, upgrades, formations, and ownership.

### Constants

```move
// Stats range
const MIN_STAT: u8 = 1;
const MAX_STAT: u8 = 100;
const STARTING_STAT_TOTAL: u64 = 150;  // split across 3 stats

// Formations (affects match math)
const FORMATION_433: u8 = 1;    // balanced, strong attack
const FORMATION_442: u8 = 2;    // balanced, strong midfield
const FORMATION_541: u8 = 3;    // defensive, weak attack
const FORMATION_352: u8 = 4;    // midfield-heavy, weak defense
const FORMATION_4231: u8 = 5;   // possession-based

// Strategy styles
const STYLE_ATTACKING: u8 = 1;  // +attack, -defense
const STYLE_BALANCED: u8 = 2;   // no modifier
const STYLE_DEFENSIVE: u8 = 3;  // +defense, -attack
const STYLE_COUNTER: u8 = 4;    // +attack vs attacking teams

// Upgrade costs (in MIST)
const STAT_UPGRADE_BASE: u64 = 100_000_000;  // 0.1 OCT per point

// Owner revenue share
const OWNER_REVENUE_BPS: u64 = 2000;  // 20% of betting revenue
```

### Structs

```move
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

    // Match record
    wins: u64,
    losses: u64,
    draws: u64,
    goals_for: u64,
    goals_against: u64,

    // Owner
    owner: address,

    // Metadata
    created_at: u64,
    total_matches: u64,
}

/// Team registry (singleton shared)
public struct TeamRegistry has key {
    id: UID,
    teams: vector<ID>,        // all registered team IDs
    admin: address,
    next_match_id: u64,
    total_matches_played: u64,
    owner_treasury: Balance<OCT>,  // accumulated owner revenue
}

/// Owner revenue claim
public struct OwnerRevenue has key, store {
    id: UID,
    owner: address,
    team_id: ID,
    amount: u64,
}
```

### Core Functions

#### `create_team(name, attack, defense, midfield, formation, strategy) → TeamNFT`
- Validates stats sum ≤ STARTING_STAT_TOTAL (150)
- Each stat must be 1-100
- Mints TeamNFT to sender
- Registers in TeamRegistry
- Costs creation fee (e.g., 1 OCT)

#### `upgrade_stat(team, stat_type, amount, payment)`
- Pay OCT to increase a stat by 1 point
- Cost = STAT_UPGRADE_BASE × current_stat_value (higher stats cost more)
- Max stat = 100
- Owner only

#### `set_formation(team, formation)`
- Owner can change formation freely (cooldown optional)

#### `set_strategy(team, strategy)`
- Owner can change strategy freely

#### `update_team_stats(team, won, goals_scored, goals_conceded)`
- Called by match engine after match
- Winners get +1 to random stat
- Losers get +1 to random stat (smaller chance)
- Updates W/L/D record
- Updates goal difference

---

## Module 2: `ai_match_engine.move` (NEW)

### Purpose
Simulates football matches between two team NFTs using deterministic stat math + One Chain randomness.

### Match Simulation Algorithm

```
fn simulate_match(team_a, team_b, random_obj):

    // Step 1: Formation modifiers (rock-paper-scissors)
    let (a_atk_mod, a_def_mod) = formation_modifier(team_a.formation, team_b.formation)
    let (b_atk_mod, b_def_mod) = formation_modifier(team_b.formation, team_a.formation)

    // Step 2: Strategy modifiers
    let (a_str_atk, a_str_def) = strategy_modifier(team_a.strategy, team_b.strategy)
    let (b_str_atk, b_str_def) = strategy_modifier(team_b.strategy, team_a.strategy)

    // Step 3: Effective stats
    let a_effective_atk = clamp(team_a.attack + a_atk_mod + a_str_atk, 1, 100)
    let a_effective_def = clamp(team_a.defense + a_def_mod + a_str_def, 1, 100)
    let b_effective_atk = clamp(team_b.attack + b_atk_mod + b_str_atk, 1, 100)
    let b_effective_def = clamp(team_b.defense + b_def_mod + b_str_def, 1, 100)

    // Step 4: Midfield control (determines possession)
    let midfield_total = team_a.midfield + team_b.midfield
    let a_possession = (team_a.midfield * 100) / midfield_total  // 0-100

    // Step 5: Goal scoring (weighted random)
    // More attacks = more chances, better defense = fewer goals conceded
    let a_chances = (a_effective_atk * a_possession) / 100
    let b_chances = (b_effective_atk * (100 - a_possession)) / 100

    let a_goals = generate_goals(random_obj, a_chances, b_effective_def)
    let b_goals = generate_goals(random_obj, b_chances, a_effective_def)

    (a_goals, b_goals)
```

### Formation Modifiers (Rock-Paper-Scissors)

| Formation | Beats | Loses To | Bonus |
|-----------|-------|----------|-------|
| 4-3-3 | 3-5-2 | 5-4-1 | +5 attack vs 352 |
| 4-4-2 | 4-2-3-1 | 4-3-3 | +5 midfield vs 4231 |
| 5-4-1 | 4-3-3 | 3-5-2 | +10 defense vs 433 |
| 3-5-2 | 5-4-1 | 4-3-3 | +10 midfield vs 541 |
| 4-2-3-1 | 4-3-3 | 4-4-2 | +5 attack vs 433 |

### Strategy Modifiers

| Strategy | Effect |
|----------|--------|
| Attacking | +8 attack, -5 defense |
| Balanced | +0, +0 |
| Defensive | -5 attack, +8 defense |
| Counter | +12 attack vs Attacking teams, -3 otherwise |

### Goal Generation

```move
fn generate_goals(random_obj, chances, opponent_defense): u8 {
    // Base goal probability
    let attack_score = (chances * 3) - opponent_defense  // can be negative
    let roll = generate_u64_in_range(random_obj, 0, 200)

    if (roll < 20 + attack_score) { 3 }       // hat trick (rare)
    else if (roll < 60 + attack_score) { 2 }   // brace
    else if (roll < 120 + attack_score) { 1 }  // single goal
    else { 0 }                                 // clean sheet
}
```

### Structs

```move
/// Match result (event + stored)
public struct MatchResult has store, copy, drop {
    match_id: u64,
    home_team_id: ID,
    away_team_id: ID,
    home_score: u8,
    away_score: u8,
    home_possession: u64,    // 0-100
    away_possession: u64,
    home_chances: u64,
    away_chances: u64,
}

/// Upcoming match (shared object for betting)
public struct ScheduledMatch has key {
    id: UID,
    match_id: u64,
    home_team_id: ID,
    away_team_id: ID,
    deadline: u64,
    settled: bool,
    result: Option<MatchResult>,
}
```

### Core Functions

#### `schedule_match(home_team, away_team, deadline) → ScheduledMatch`
- Admin or auto-scheduler creates match
- Creates shared object for betting

#### `settle_match(scheduled_match, home_team, away_team, random_obj, clock)`
- Runs simulation algorithm
- Updates team stats (wins/losses/goals)
- Stores result in ScheduledMatch
- Emits MatchResult event

#### `auto_schedule_round(registry, teams[], random_obj, clock)`
- Pairs all registered teams randomly
- Creates ScheduledMatch for each pair
- Uses Fisher-Yates shuffle for pairings

---

## Module 3: `betting_pool.move` (MODIFIED)

### Changes from Current

Add integration functions:

#### `seed_team_match(vault, match, home_team, away_team)`
- Creates MatchAccounting for the scheduled match
- Calculates odds from team stats:
  ```
  home_strength = (home.attack + home.defense + home.midfield) / 3
  away_strength = (away.attack + away.defense + away.midfield) / 3
  // Weighted with home advantage (+5)
  // Convert to compressed odds (1.2x - 1.8x)
  ```

#### `settle_from_match_result(accounting, result)`
- HOME_WIN if home_score > away_score
- AWAY_WIN if away_score > home_score
- DRAW if equal

#### `distribute_owner_revenue(team, amount)`
- OWNER_REVENUE_BPS (20%) of net revenue goes to team owner
- Claimable via OwnerRevenue object

---

## User Flows

### Flow 1: Create & Manage Team

```
1. User connects OneWallet
2. Pays 1 OCT creation fee
3. Allocates 150 stat points across attack/defense/midfield
4. Chooses formation (4-3-3, 4-4-2, etc.)
5. Chooses strategy (attacking, balanced, defensive, counter)
6. Receives TeamNFT in wallet
7. Team is registered and enters rotation
```

### Flow 2: Upgrade Team

```
1. Owner views their TeamNFT
2. Selects stat to upgrade (attack/defense/midfield)
3. Pays OCT (cost = base × current_value)
4. Stat increases by 1
5. Can change formation/strategy for free
```

### Flow 3: Spectator Betting

```
1. Spectator views upcoming matches
2. Sees team stats + AI-calculated odds
3. Places bet (HOME_WIN / DRAW / AWAY_WIN)
4. Waits for match to settle
5. Claims winnings if correct
```

### Flow 4: Match Simulation

```
1. Auto-scheduler pairs teams randomly
2. ScheduledMatch created (shared object)
3. Betting opens (odds locked from team stats)
4. Deadline reached → settle_match() called
5. Simulation runs → result emitted
6. Teams updated (wins/losses/goals)
7. Bets settled → winners claim
```

### Flow 5: Owner Revenue

```
1. Match betting pool generates revenue (5% platform fee)
2. 20% of net revenue allocated to team owners
3. Split between home/away team owners (50/50)
4. Owner claims via OwnerRevenue object
```

---

## Progression System

### Team Evolution

| Action | Effect |
|--------|--------|
| Win match | +1 random stat (weighted toward attack/midfield) |
| Lose match | +1 random stat (weighted toward defense, lower chance) |
| Draw match | +1 to lowest stat (balance improvement) |
| Clean sheet | +2 to defense |
| Score 3+ goals | +2 to attack |
| Win streak (3+) | +1 to all stats |

### Team Records

| Metric | Tracked |
|--------|---------|
| Win rate | `wins / total_matches` |
| Goal difference | `goals_for - goals_against` |
| Form | last 5 results (W/D/L) |
| Average possession | from match results |

### Leaderboard

Teams ranked by:
1. Points (3 for win, 1 for draw, 0 for loss) — primary
2. Goal difference — tiebreaker
3. Goals scored — second tiebreaker

---

## On-Chain Data Flow

```
TeamNFT created
    │
    ▼
Auto-scheduler pairs teams
    │
    ▼
MatchCreated ──► OddsLocked ──► BettingOpens
    │                                    │
    │                           Bets placed (BetPlaced)
    │
    ▼
SettleMatch(random_obj)
    │
    ├──► MatchResult{home_score, away_score, possession, chances}
    │
    ├──► TeamNFT updated (stats, W/L/D, goals)
    │
    ├──► Bets settled (WinningsClaimed / BetLost)
    │
    └──► OwnerRevenue allocated
```

---

## File Structure

```
gasless-superapp/leaguealpha/
├── sources/
│   ├── betting_pool.move        (existing, modified)
│   ├── game_engine.move         (existing, keep for standalone matches)
│   ├── team_nft.move            (NEW)
│   └── ai_match_engine.move     (NEW)
├── tests/
│   └── leaguealpha_tests.move   (updated)
├── Move.toml
├── DESIGN.md                    (this file)
└── DEPLOYMENT.md
```

---

## Risk Management

| Risk | Mitigation |
|------|-----------|
| Stat imbalance | Starting total capped at 150, upgrades cost exponentially more |
| Dominant formations | Rock-paper-scissors ensures no single formation dominates |
| LP losses | Odds compressed to 1.2x-1.8x, seed capped at 3,000 OCT |
| Bet size limits | MAX_BET = 10,000 OCT, MAX_PAYOUT = 100,000 OCT |
| Team hoarding | Creation fee (1 OCT), max teams per address optional |
| Front-running | Odds locked at match creation, no in-match betting |
