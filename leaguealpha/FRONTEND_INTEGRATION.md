# LeagueAlpha Frontend Integration Guide

Complete guide for integrating the LeagueAlpha football manager + betting protocol.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Package IDs & Shared Objects](#package-ids--shared-objects)
3. [Constants](#constants)
4. [Module: team_nft](#module-team_nft)
5. [Module: ai_match_engine](#module-ai_match_engine)
6. [Module: betting_pool](#module-betting_pool)
7. [User Flows](#user-flows)
8. [React Hooks](#react-hooks)
9. [Event Indexing](#event-indexing)
10. [Error Codes](#error-codes)

---

## Architecture Overview

```
┌─────────────┐     ┌──────────────────┐     ┌──────────────┐
│  team_nft   │────▶│ ai_match_engine  │────▶│ betting_pool │
│ (Team NFTs) │     │ (Match Sim)      │     │ (LP + Bets)  │
└─────────────┘     └──────────────────┘     └──────────────┘
      │                      │                       │
  create_team         schedule_match          add_liquidity
  upgrade_stat        settle_match            seed_match
  set_strategy                                place_bet
  set_formation                               claim_winnings
                                              finalize_match_revenue
```

**Three modules, clear separation:**
- `team_nft` — Team NFTs with stats, formations, strategies, momentum
- `ai_match_engine` — Stat-weighted match simulation with randomness
- `betting_pool` — LP-funded betting pool with per-match escrow

---

## Package IDs & Shared Objects

```ts
// === Replace these with your deployed IDs ===
export const LEAGUE_PACKAGE_ID = "0xYOUR_PACKAGE_ID";

// Shared objects (created on init)
export const TEAM_REGISTRY_ID    = "0xTEAM_REGISTRY_ID";    // team_nft::TeamRegistry
export const MATCH_ENGINE_ID     = "0xMATCH_ENGINE_ID";     // ai_match_engine::MatchEngine
export const LIQUIDITY_VAULT_ID  = "0xLIQUIDITY_VAULT_ID";  // betting_pool::LiquidityVault

// Clock (same on all networks)
export const CLOCK_OBJECT = "0x6";
```

---

## Constants

```ts
// === Strategy Types (Risk-Based) ===
export const Strategy = {
  GEGENPRESSING: 1,  // +15 atk, -10 def, +10 atk if winning
  BALANCED:      2,  // No modifiers
  PARK_THE_BUS:  3,  // -15 atk, +20 def, draws more likely
  COUNTER:       4,  // +8 atk, +3 def, +15 atk vs >60 atk opponent
  TIKI_TAKA:     5,  // +5 atk, +5 def, +15 midfield
  LONG_BALL:     6,  // +10 atk, -5 def, bypasses midfield
} as const;

// === Formation Types ===
export const Formation = {
  F_433:  1,
  F_442:  2,
  F_541:  3,
  F_352:  4,
  F_4231: 5,
} as const;

// === Formation-Strategy Synergy Bonuses ===
export const SYNERGIES: Record<number, { strategy: number; bonus: string }> = {
  [Formation.F_4231]: { strategy: Strategy.TIKI_TAKA,      bonus: "+5 all stats" },
  [Formation.F_433]:  { strategy: Strategy.GEGENPRESSING,  bonus: "+8 attack" },
  [Formation.F_541]:  { strategy: Strategy.COUNTER,        bonus: "+10 defense" },
  [Formation.F_352]:  { strategy: Strategy.LONG_BALL,      bonus: "+10 attack" },
  [Formation.F_541]:  { strategy: Strategy.PARK_THE_BUS,   bonus: "+15 defense" },
};

// === Bet Outcome ===
export const Outcome = {
  HOME_WIN: 1,
  AWAY_WIN: 2,
  DRAW:     3,
} as const;

// === Team Stats ===
export const MAX_STAT = 100;
export const STARTING_STAT_TOTAL = 150;
export const CREATION_FEE = 1_000_000_000; // 1 OCT in MIST

// === Betting ===
export const SEED_PER_MATCH = 3_000_000_000_000; // 3,000 OCT
export const MAX_BET_AMOUNT = 10_000_000_000_000; // 10,000 OCT
export const PROTOCOL_FEE_BPS = 500; // 5%

// === Strategy Lock ===
export const STRATEGY_LOCK_DURATION_MS = 3_600_000; // 1 hour

// Scale constants
export const SCALE_18 = 1_000_000_000_000_000_000n; // 1e18
export const MIST_PER_OCT = 1_000_000_000;
```

---

## Module: `team_nft`

### Struct: `TeamNFT`

```
TeamNFT {
  id: UID,
  name: String,
  attack: u8,              // 1-100
  defense: u8,             // 1-100
  midfield: u8,            // 1-100
  formation: u8,           // 1-5
  strategy: u8,            // 1-6
  strategy_locked_at: u64, // timestamp_ms until strategy is locked
  wins: u64,
  losses: u64,
  draws: u64,
  goals_for: u64,
  goals_against: u64,
  last_5_results: vector<u8>, // 1=win, 2=loss, 3=draw
  owner: address,
  created_at: u64,
  total_matches: u64,
}
```

### `create_team`

Create a new team NFT.

```move
public entry fun create_team(
    registry: &mut TeamRegistry,
    name: vector<u8>,        // Team name as bytes
    attack: u8,              // 1-100, must sum with def+mid <= 150
    defense: u8,             // 1-100
    midfield: u8,            // 1-100
    formation: u8,           // 1=433, 2=442, 3=541, 4=352, 5=4231
    strategy: u8,            // 1-6 (see Strategy enum)
    payment: Coin<OCT>,      // >= 1 OCT (CREATION_FEE)
    clock: &Clock,
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
import { Transaction } from '@mysten/sui/transactions';

async function createTeam(name: string, atk: number, def: number, mid: number, formation: number, strategy: number) {
  const tx = new Transaction();

  // Split creation fee from gas coin
  const [payment] = tx.splitCoins(tx.gas, [1_000_000_000]); // 1 OCT

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::team_nft::create_team`,
    arguments: [
      tx.object(TEAM_REGISTRY_ID),
      tx.pure.string(name),
      tx.pure.u8(atk),
      tx.pure.u8(def),
      tx.pure.u8(mid),
      tx.pure.u8(formation),
      tx.pure.u8(strategy),
      payment,
      tx.object(CLOCK_OBJECT),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

**Validation rules:**
- `attack + defense + midfield <= 150`
- Each stat: 1-100
- Formation: 1-5
- Strategy: 1-6
- Payment >= 1 OCT

### `upgrade_stat`

Upgrade a single stat by 1 point. Cost scales with current value.

```move
public entry fun upgrade_stat(
    team: &mut TeamNFT,
    registry: &mut TeamRegistry,
    stat_type: u8,           // 1=attack, 2=defense, 3=midfield
    payment: Coin<OCT>,      // cost = BASE * current_value (0.1 OCT * current)
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function upgradeStat(teamId: string, statType: 1 | 2 | 3, currentValue: number) {
  const tx = new Transaction();
  const cost = 100_000_000 * currentValue; // STAT_UPGRADE_BASE * current

  const [payment] = tx.splitCoins(tx.gas, [cost]);

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::team_nft::upgrade_stat`,
    arguments: [
      tx.object(teamId),
      tx.object(TEAM_REGISTRY_ID),
      tx.pure.u8(statType),
      payment,
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### `set_strategy`

Change team strategy. **Locked for 1 hour after change** (commitment system).

```move
public entry fun set_strategy(
    team: &mut TeamNFT,
    strategy: u8,    // 1-6
    clock: &Clock,   // Used to check lock
    ctx: &TxContext
)
```

**Frontend call:**

```ts
async function setStrategy(teamId: string, strategy: number) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::team_nft::set_strategy`,
    arguments: [
      tx.object(teamId),
      tx.pure.u8(strategy),
      tx.object(CLOCK_OBJECT),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

**Error if locked:** `E_STRATEGY_LOCKED (8)` — must wait until `strategy_locked_at` has passed.

### `set_formation`

Change team formation. No lock, free to change anytime.

```move
public entry fun set_formation(
    team: &mut TeamNFT,
    formation: u8,   // 1-5
    ctx: &TxContext
)
```

**Frontend call:**

```ts
async function setFormation(teamId: string, formation: number) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::team_nft::set_formation`,
    arguments: [
      tx.object(teamId),
      tx.pure.u8(formation),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### View Functions

```move
// Returns (attack, defense, midfield, formation, strategy)
public fun get_team_stats(team: &TeamNFT): (u8, u8, u8, u8, u8)

// Returns (wins, losses, draws, goals_for, goals_against)
public fun get_team_record(team: &TeamNFT): (u64, u64, u64, u64, u64)

public fun get_team_name(team: &TeamNFT): String
public fun get_team_owner(team: &TeamNFT): address
public fun get_team_id(team: &TeamNFT): ID
public fun get_formation(team: &TeamNFT): u8
public fun get_strategy(team: &TeamNFT): u8
public fun get_total_matches(team: &TeamNFT): u64
public fun get_team_strength(team: &TeamNFT): u64  // avg(atk, def, mid)

// Strategy lock
public fun get_strategy_locked_at(team: &TeamNFT): u64
public fun can_change_strategy(team: &TeamNFT, clock: &Clock): bool

// Momentum
public fun get_last_5_results(team: &TeamNFT): vector<u8>
public fun get_momentum_bonus(team: &TeamNFT): (u64, u64, u64) // (atk_bonus, def_bonus, mid_bonus)
public fun has_morale_debuff(team: &TeamNFT): bool // true if 4+ losses in last 5
```

**Reading team data from frontend:**

```ts
async function getTeamData(teamId: string) {
  const obj = await suiClient.getObject({
    id: teamId,
    options: { showContent: true },
  });

  if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') return null;

  const f = (obj.data.content as any).fields;

  return {
    name: f.name,
    attack: Number(f.attack),
    defense: Number(f.defense),
    midfield: Number(f.midfield),
    formation: Number(f.formation),
    strategy: Number(f.strategy),
    strategyLockedAt: Number(f.strategy_locked_at),
    wins: Number(f.wins),
    losses: Number(f.losses),
    draws: Number(f.draws),
    goalsFor: Number(f.goals_for),
    goalsAgainst: Number(f.goals_against),
    last5Results: (f.last_5_results || []).map(Number),
    totalMatches: Number(f.total_matches),
    owner: f.owner,
  };
}
```

---

## Module: `ai_match_engine`

### Struct: `ScheduledMatch`

```
ScheduledMatch {
  id: UID,
  match_id: u64,
  home_team_id: ID,
  away_team_id: ID,
  deadline: u64,
  settled: bool,
  result: Option<MatchResult>,
}
```

### Struct: `MatchResult`

```
MatchResult {
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
```

### `schedule_match`

Schedule a match between two teams. **Permissionless** — anyone can call.

```move
public entry fun schedule_match(
    engine: &mut MatchEngine,
    home_team: &TeamNFT,
    away_team: &TeamNFT,
    duration_ms: u64,    // Time until match can be settled
    clock: &Clock,
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function scheduleMatch(homeTeamId: string, awayTeamId: string, durationMs: number) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::ai_match_engine::schedule_match`,
    arguments: [
      tx.object(MATCH_ENGINE_ID),
      tx.object(homeTeamId),
      tx.object(awayTeamId),
      tx.pure.u64(durationMs),
      tx.object(CLOCK_OBJECT),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### `settle_match`

Settle a scheduled match. Requires deadline to have passed + One Chain randomness.

```move
#[allow(lint(public_random))]
public entry fun settle_match(
    scheduled: &mut ScheduledMatch,
    home_team: &mut TeamNFT,
    away_team: &mut TeamNFT,
    _engine: &mut MatchEngine,
    random_obj: &Random,   // One Chain randomness object
    clock: &Clock,
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
// The Random object is a system-level shared object on One Chain
const RANDOM_OBJECT = "0x8"; // Verify on your network

async function settleMatch(scheduledMatchId: string, homeTeamId: string, awayTeamId: string) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::ai_match_engine::settle_match`,
    arguments: [
      tx.object(scheduledMatchId),
      tx.object(homeTeamId),
      tx.object(awayTeamId),
      tx.object(MATCH_ENGINE_ID),
      tx.object(RANDOM_OBJECT),
      tx.object(CLOCK_OBJECT),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### Settlement Pipeline (what happens on-chain)

1. **Formation modifiers** — rock-paper-scissors matchups
2. **Strategy modifiers** — risk/reward bonuses
3. **Formation-strategy synergy** — bonus if paired correctly
4. **Momentum bonuses** — from last 5 results
5. **Midfield control** — with Long Ball bypass
6. **Goal generation** — with Park the Bus draw bias

### View Functions

```move
public fun is_match_settled(scheduled: &ScheduledMatch): bool
public fun get_match_id(scheduled: &ScheduledMatch): u64
public fun get_match_teams(scheduled: &ScheduledMatch): (ID, ID)
public fun get_match_deadline(scheduled: &ScheduledMatch): u64
public fun get_match_result(scheduled: &ScheduledMatch): &Option<MatchResult>
public fun get_result_scores(result: &MatchResult): (u8, u8)
public fun get_result_possession(result: &MatchResult): (u64, u64)
public fun get_match_outcome(scheduled: &ScheduledMatch): u8 // 1=home, 2=away, 3=draw
public fun get_match_summary(scheduled: &ScheduledMatch): (u8, u8, u64, u64)
```

**Reading match data:**

```ts
async function getMatchResult(scheduledMatchId: string) {
  const obj = await suiClient.getObject({
    id: scheduledMatchId,
    options: { showContent: true },
  });

  if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') return null;

  const f = (obj.data.content as any).fields;

  return {
    matchId: Number(f.match_id),
    homeTeamId: f.home_team_id,
    awayTeamId: f.away_team_id,
    deadline: Number(f.deadline),
    settled: f.settled,
    result: f.result?.fields ? {
      homeScore: Number(f.result.fields.home_score),
      awayScore: Number(f.result.fields.away_score),
      homePossession: Number(f.result.fields.home_possession),
      awayPossession: Number(f.result.fields.away_possession),
    } : null,
  };
}
```

---

## Module: `betting_pool`

### Struct: `LiquidityVault`

```
LiquidityVault {
  id: UID,
  balance: Balance<OCT>,              // Global LP pool
  total_lp_shares: u64,
  lp_positions: Table<address, u64>,  // address => shares
  protocol_treasury: address,
  season_reward_pool: Balance<OCT>,
  admin: address,
  next_bet_id: u64,
  seeded_matches: Table<u64, bool>,   // match_id => seeded
}
```

### Struct: `MatchAccounting`

```
MatchAccounting {
  id: UID,
  match_id: u64,
  pool: MatchPool,          // { home_win_pool, away_win_pool, draw_pool, total_pool }
  odds: LockedOdds,         // { home_odds, away_odds, draw_odds } (1e18 scale)
  total_bet_volume: u64,
  total_paid_out: u64,
  protocol_fee_collected: u64,
  lp_borrowed: u64,
  seed_amount: u64,
  escrow: Balance<OCT>,     // Per-match escrow (holds real OCT)
  seeded: bool,
}
```

### Struct: `Bet`

```
Bet {
  id: UID,
  bet_id: u64,
  bettor: address,
  match_id: u64,
  amount: u64,                    // Total bet amount
  amount_after_fee: u64,          // After 5% protocol fee
  locked_multiplier: u64,         // 1e18 = 1.0x (single outcome)
  predictions: vector<Prediction>, // Single prediction
  settled: bool,
  claimed: bool,
}
```

### Struct: `LPToken`

```
LPToken {
  id: UID,
  shares: u64,
}
// NON-TRANSFERABLE (key only, no store)
```

---

### `add_liquidity`

Deposit OCT into the liquidity vault to earn LP shares.

```move
public entry fun add_liquidity(
    vault: &mut LiquidityVault,
    payment: Coin<OCT>,
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function addLiquidity(amountOct: number) {
  const tx = new Transaction();
  const amountMist = amountOct * 1_000_000_000;

  const [payment] = tx.splitCoins(tx.gas, [amountMist]);

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::betting_pool::add_liquidity`,
    arguments: [
      tx.object(LIQUIDITY_VAULT_ID),
      payment,
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### `remove_liquidity`

Burn LP token to withdraw proportional share of vault.

```move
public entry fun remove_liquidity(
    vault: &mut LiquidityVault,
    lp_token: LPToken,   // Consumed (burned)
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function removeLiquidity(lpTokenId: string) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::betting_pool::remove_liquidity`,
    arguments: [
      tx.object(LIQUIDITY_VAULT_ID),
      tx.object(lpTokenId),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### `seed_match`

Admin-only. Seed a match pool with differentiated odds. **Actually moves OCT from vault to per-match escrow.**

```move
public entry fun seed_match(
    vault: &mut LiquidityVault,
    match_data: &MatchData,   // From game_engine
    ctx: &mut TxContext
)
```

### `seed_team_match`

Admin-only. Seed from team NFT stats. **Actually moves OCT from vault to per-match escrow.**

```move
public entry fun seed_team_match(
    vault: &mut LiquidityVault,
    scheduled: &ScheduledMatch,   // From ai_match_engine
    home_team: &TeamNFT,
    away_team: &TeamNFT,
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function seedTeamMatch(scheduledMatchId: string, homeTeamId: string, awayTeamId: string) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::betting_pool::seed_team_match`,
    arguments: [
      tx.object(LIQUIDITY_VAULT_ID),
      tx.object(scheduledMatchId),
      tx.object(homeTeamId),
      tx.object(awayTeamId),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

**Important:** Each `match_id` can only be seeded once. Duplicate attempt fails with `E_MATCH_ALREADY_SEEDED`.

### `place_bet`

Place a single-outcome bet. **Funds go into match escrow, not global vault.**

```move
public entry fun place_bet(
    accounting: &mut MatchAccounting,
    vault: &mut LiquidityVault,
    outcome: u8,             // 1=home win, 2=away win, 3=draw
    payment: Coin<OCT>,      // Bet amount (max 10,000 OCT)
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function placeBet(matchAccountingId: string, outcome: 1 | 2 | 3, amountOct: number) {
  const tx = new Transaction();
  const amountMist = amountOct * 1_000_000_000;

  const [payment] = tx.splitCoins(tx.gas, [amountMist]);

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::betting_pool::place_bet`,
    arguments: [
      tx.object(matchAccountingId),
      tx.object(LIQUIDITY_VAULT_ID),
      tx.pure.u8(outcome),
      payment,
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

**Odds display:** Read `LockedOdds` from `MatchAccounting` to show potential payout:

```ts
function calculatePotentialPayout(
  betAmount: number,
  odds: bigint,       // 1e18 scale
  feeBps: number = 500
): number {
  const afterFee = betAmount * (1 - feeBps / 10000);
  return Number((BigInt(Math.floor(afterFee * 1e9)) * odds) / SCALE_18) / 1e9;
}
```

### `claim_winnings`

Claim payout for a winning bet after match settlement. **Pays from match escrow.**

```move
public entry fun claim_winnings(
    bet: &mut Bet,
    accounting: &mut MatchAccounting,
    match_data: &MatchData,    // Must be settled
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function claimWinnings(betId: string, matchAccountingId: string, matchDataId: string) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::betting_pool::claim_winnings`,
    arguments: [
      tx.object(betId),
      tx.object(matchAccountingId),
      tx.object(matchDataId),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### `claim_team_winnings`

Claim payout for team-based match bet.

```move
public entry fun claim_team_winnings(
    bet: &mut Bet,
    accounting: &mut MatchAccounting,
    scheduled: &ScheduledMatch,  // Must be settled
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function claimTeamWinnings(betId: string, matchAccountingId: string, scheduledMatchId: string) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::betting_pool::claim_team_winnings`,
    arguments: [
      tx.object(betId),
      tx.object(matchAccountingId),
      tx.object(scheduledMatchId),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### `finalize_match_revenue`

Admin-only. Moves escrow remainder to vault and season pool. **Must be called after all claims.**

```move
public entry fun finalize_match_revenue(
    accounting: &mut MatchAccounting,
    vault: &mut LiquidityVault,
    ctx: &mut TxContext
)
```

**Frontend call:**

```ts
async function finalizeMatchRevenue(matchAccountingId: string) {
  const tx = new Transaction();

  tx.moveCall({
    target: `${LEAGUE_PACKAGE_ID}::betting_pool::finalize_match_revenue`,
    arguments: [
      tx.object(matchAccountingId),
      tx.object(LIQUIDITY_VAULT_ID),
    ],
  });

  return signAndExecute({ transaction: tx });
}
```

### View Functions

```move
public fun get_locked_odds(accounting: &MatchAccounting): &LockedOdds
public fun get_match_pool(accounting: &MatchAccounting): &MatchPool
public fun is_match_seeded(accounting: &MatchAccounting): bool
public fun get_match_id(accounting: &MatchAccounting): u64
public fun get_protocol_fee_collected(accounting: &MatchAccounting): u64
public fun get_total_bet_volume(accounting: &MatchAccounting): u64
public fun get_escrow_balance(accounting: &MatchAccounting): u64
```

---

## User Flows

### Flow 1: LP Provider

```
1. add_liquidity(amount)     → Receives LPToken
2. ... time passes, LP earns from protocol fees ...
3. remove_liquidity(lpToken) → Burns token, receives OCT + profit
```

### Flow 2: Team Owner

```
1. create_team(name, atk, def, mid, formation, strategy)
2. upgrade_stat(team, statType)  → Repeat to grow stats
3. set_formation(team, formation) → Free anytime
4. set_strategy(team, strategy)   → Locked for 1 hour after change
5. ... match happens ...
6. Check results via get_match_result(scheduledMatch)
7. Team stats auto-update on settlement (wins/losses/momentum)
```

### Flow 3: Bettor

```
1. Browse available matches (query ScheduledMatch or MatchAccounting events)
2. Check locked odds from MatchAccounting
3. place_bet(accounting, outcome, amount) → Receives Bet NFT
4. Wait for match to settle
5. If won: claim_winnings(bet, accounting, matchData) → Receives OCT
6. If lost: Bet NFT is worthless (emits BetLost event)
```

### Flow 4: Admin (Match Lifecycle)

```
1. schedule_match(engine, homeTeam, awayTeam, duration) → Creates ScheduledMatch
2. seed_team_match(vault, scheduled, homeTeam, awayTeam) → Creates MatchAccounting, moves 3000 OCT to escrow
3. ... users place bets ...
4. Wait for deadline to pass
5. settle_match(scheduled, homeTeam, awayTeam, engine, random, clock) → Scores generated
6. ... users claim winnings from escrow ...
7. finalize_match_revenue(accounting, vault) → Returns remaining escrow to vault + season pool
```

---

## React Hooks

### `useTeamActions`

```ts
import { useState, useCallback } from 'react';
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';

const LEAGUE_PACKAGE_ID = "0xYOUR_PACKAGE";
const TEAM_REGISTRY_ID = "0xYOUR_REGISTRY";
const CLOCK_OBJECT = "0x6";

export function useTeamActions() {
  const currentAccount = useCurrentAccount();
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction();
  const suiClient = useSuiClient();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const createTeam = useCallback(async (
    name: string,
    attack: number,
    defense: number,
    midfield: number,
    formation: number,
    strategy: number
  ) => {
    if (!currentAccount) throw new Error('Wallet not connected');

    setIsLoading(true);
    setError(null);

    try {
      const tx = new Transaction();
      const [payment] = tx.splitCoins(tx.gas, [1_000_000_000]); // 1 OCT

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::team_nft::create_team`,
        arguments: [
          tx.object(TEAM_REGISTRY_ID),
          tx.pure.string(name),
          tx.pure.u8(attack),
          tx.pure.u8(defense),
          tx.pure.u8(midfield),
          tx.pure.u8(formation),
          tx.pure.u8(strategy),
          payment,
          tx.object(CLOCK_OBJECT),
        ],
      });

      const result = await signAndExecute({ transaction: tx });
      return result.digest;
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed');
      throw err;
    } finally {
      setIsLoading(false);
    }
  }, [currentAccount, signAndExecute]);

  const upgradeStat = useCallback(async (teamId: string, statType: 1 | 2 | 3, currentValue: number) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);

    try {
      const tx = new Transaction();
      const cost = 100_000_000 * currentValue;
      const [payment] = tx.splitCoins(tx.gas, [cost]);

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::team_nft::upgrade_stat`,
        arguments: [
          tx.object(teamId),
          tx.object(TEAM_REGISTRY_ID),
          tx.pure.u8(statType),
          payment,
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally {
      setIsLoading(false);
    }
  }, [currentAccount, signAndExecute]);

  const setStrategy = useCallback(async (teamId: string, strategy: number) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);

    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::team_nft::set_strategy`,
        arguments: [
          tx.object(teamId),
          tx.pure.u8(strategy),
          tx.object(CLOCK_OBJECT),
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally {
      setIsLoading(false);
    }
  }, [currentAccount, signAndExecute]);

  const setFormation = useCallback(async (teamId: string, formation: number) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);

    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::team_nft::set_formation`,
        arguments: [
          tx.object(teamId),
          tx.pure.u8(formation),
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally {
      setIsLoading(false);
    }
  }, [currentAccount, signAndExecute]);

  // === View: Read team data ===
  const getTeam = useCallback(async (teamId: string) => {
    const obj = await suiClient.getObject({
      id: teamId,
      options: { showContent: true },
    });

    if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') return null;
    const f = (obj.data.content as any).fields;

    return {
      name: f.name,
      attack: Number(f.attack),
      defense: Number(f.defense),
      midfield: Number(f.midfield),
      formation: Number(f.formation),
      strategy: Number(f.strategy),
      strategyLockedAt: Number(f.strategy_locked_at),
      wins: Number(f.wins),
      losses: Number(f.losses),
      draws: Number(f.draws),
      last5Results: (f.last_5_results || []).map(Number),
      totalMatches: Number(f.total_matches),
    };
  }, [suiClient]);

  return {
    createTeam,
    upgradeStat,
    setStrategy,
    setFormation,
    getTeam,
    isLoading,
    error,
  };
}
```

### `useBettingActions`

```ts
import { useState, useCallback } from 'react';
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';

const LEAGUE_PACKAGE_ID = "0xYOUR_PACKAGE";
const LIQUIDITY_VAULT_ID = "0xYOUR_VAULT";
const MIST_PER_OCT = 1_000_000_000;

export function useBettingActions() {
  const currentAccount = useCurrentAccount();
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction();
  const suiClient = useSuiClient();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // === LP Actions ===

  const addLiquidity = useCallback(async (octAmount: number) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);
    try {
      const tx = new Transaction();
      const [payment] = tx.splitCoins(tx.gas, [octAmount * MIST_PER_OCT]);

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::betting_pool::add_liquidity`,
        arguments: [tx.object(LIQUIDITY_VAULT_ID), payment],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally { setIsLoading(false); }
  }, [currentAccount, signAndExecute]);

  const removeLiquidity = useCallback(async (lpTokenId: string) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);
    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::betting_pool::remove_liquidity`,
        arguments: [tx.object(LIQUIDITY_VAULT_ID), tx.object(lpTokenId)],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally { setIsLoading(false); }
  }, [currentAccount, signAndExecute]);

  // === Betting Actions ===

  const placeBet = useCallback(async (
    matchAccountingId: string,
    outcome: 1 | 2 | 3,
    octAmount: number
  ) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);
    try {
      const tx = new Transaction();
      const [payment] = tx.splitCoins(tx.gas, [octAmount * MIST_PER_OCT]);

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::betting_pool::place_bet`,
        arguments: [
          tx.object(matchAccountingId),
          tx.object(LIQUIDITY_VAULT_ID),
          tx.pure.u8(outcome),
          payment,
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally { setIsLoading(false); }
  }, [currentAccount, signAndExecute]);

  const claimWinnings = useCallback(async (
    betId: string,
    matchAccountingId: string,
    matchDataId: string
  ) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);
    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::betting_pool::claim_winnings`,
        arguments: [
          tx.object(betId),
          tx.object(matchAccountingId),
          tx.object(matchDataId),
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally { setIsLoading(false); }
  }, [currentAccount, signAndExecute]);

  const claimTeamWinnings = useCallback(async (
    betId: string,
    matchAccountingId: string,
    scheduledMatchId: string
  ) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);
    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::betting_pool::claim_team_winnings`,
        arguments: [
          tx.object(betId),
          tx.object(matchAccountingId),
          tx.object(scheduledMatchId),
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally { setIsLoading(false); }
  }, [currentAccount, signAndExecute]);

  // === View: Read pool/match data ===

  const getMatchAccounting = useCallback(async (accountingId: string) => {
    const obj = await suiClient.getObject({
      id: accountingId,
      options: { showContent: true },
    });

    if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') return null;
    const f = (obj.data.content as any).fields;

    return {
      matchId: Number(f.match_id),
      seeded: f.seeded,
      pool: {
        homeWinPool: Number(f.pool.fields.home_win_pool),
        awayWinPool: Number(f.pool.fields.away_win_pool),
        drawPool: Number(f.pool.fields.draw_pool),
        totalPool: Number(f.pool.fields.total_pool),
      },
      odds: {
        homeOdds: BigInt(f.odds.fields.home_odds),
        awayOdds: BigInt(f.odds.fields.away_odds),
        drawOdds: BigInt(f.odds.fields.draw_odds),
      },
      totalBetVolume: Number(f.total_bet_volume),
      totalPaidOut: Number(f.total_paid_out),
      escrowBalance: Number(f.escrow),
    };
  }, [suiClient]);

  const getBet = useCallback(async (betId: string) => {
    const obj = await suiClient.getObject({
      id: betId,
      options: { showContent: true },
    });

    if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') return null;
    const f = (obj.data.content as any).fields;

    return {
      betId: Number(f.bet_id),
      bettor: f.bettor,
      matchId: Number(f.match_id),
      amount: Number(f.amount),
      amountAfterFee: Number(f.amount_after_fee),
      settled: f.settled,
      claimed: f.claimed,
      predictions: (f.predictions || []).map((p: any) => ({
        matchIndex: Number(p.fields.match_index),
        predictedOutcome: Number(p.fields.predicted_outcome),
        amountInPool: Number(p.fields.amount_in_pool),
      })),
    };
  }, [suiClient]);

  return {
    addLiquidity,
    removeLiquidity,
    placeBet,
    claimWinnings,
    claimTeamWinnings,
    getMatchAccounting,
    getBet,
    isLoading,
    error,
  };
}
```

### `useMatchActions`

```ts
import { useState, useCallback } from 'react';
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';

const LEAGUE_PACKAGE_ID = "0xYOUR_PACKAGE";
const MATCH_ENGINE_ID = "0xYOUR_ENGINE";
const RANDOM_OBJECT = "0x8";
const CLOCK_OBJECT = "0x6";

export function useMatchActions() {
  const currentAccount = useCurrentAccount();
  const { mutateAsync: signAndExecute } = useSignAndExecuteTransaction();
  const suiClient = useSuiClient();
  const [isLoading, setIsLoading] = useState(false);

  const scheduleMatch = useCallback(async (
    homeTeamId: string,
    awayTeamId: string,
    durationMs: number
  ) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);
    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::ai_match_engine::schedule_match`,
        arguments: [
          tx.object(MATCH_ENGINE_ID),
          tx.object(homeTeamId),
          tx.object(awayTeamId),
          tx.pure.u64(durationMs),
          tx.object(CLOCK_OBJECT),
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally { setIsLoading(false); }
  }, [currentAccount, signAndExecute]);

  const settleMatch = useCallback(async (
    scheduledMatchId: string,
    homeTeamId: string,
    awayTeamId: string
  ) => {
    if (!currentAccount) throw new Error('Wallet not connected');
    setIsLoading(true);
    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${LEAGUE_PACKAGE_ID}::ai_match_engine::settle_match`,
        arguments: [
          tx.object(scheduledMatchId),
          tx.object(homeTeamId),
          tx.object(awayTeamId),
          tx.object(MATCH_ENGINE_ID),
          tx.object(RANDOM_OBJECT),
          tx.object(CLOCK_OBJECT),
        ],
      });

      return (await signAndExecute({ transaction: tx })).digest;
    } finally { setIsLoading(false); }
  }, [currentAccount, signAndExecute]);

  const getScheduledMatch = useCallback(async (matchId: string) => {
    const obj = await suiClient.getObject({
      id: matchId,
      options: { showContent: true },
    });

    if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') return null;
    const f = (obj.data.content as any).fields;

    return {
      matchId: Number(f.match_id),
      homeTeamId: f.home_team_id,
      awayTeamId: f.away_team_id,
      deadline: Number(f.deadline),
      settled: f.settled,
      result: f.result?.fields ? {
        homeScore: Number(f.result.fields.home_score),
        awayScore: Number(f.result.fields.away_score),
        homePossession: Number(f.result.fields.home_possession),
        awayPossession: Number(f.result.fields.away_possession),
        homeEffectiveAtk: Number(f.result.fields.home_effective_atk),
        homeEffectiveDef: Number(f.result.fields.home_effective_def),
        awayEffectiveAtk: Number(f.result.fields.away_effective_atk),
        awayEffectiveDef: Number(f.result.fields.away_effective_def),
      } : null,
    };
  }, [suiClient]);

  return {
    scheduleMatch,
    settleMatch,
    getScheduledMatch,
    isLoading,
  };
}
```

---

## Event Indexing

Use these event types to build activity feeds and track protocol usage.

### team_nft Events

```ts
// Team created
`${LEAGUE_PACKAGE_ID}::team_nft::TeamCreated`
// Fields: { team_id, owner, name, attack, defense, midfield, formation, strategy }

// Strategy changed
`${LEAGUE_PACKAGE_ID}::team_nft::TeamStrategyChanged`
// Fields: { team_id, old_strategy, new_strategy }

// Formation changed
`${LEAGUE_PACKAGE_ID}::team_nft::TeamFormationChanged`
// Fields: { team_id, old_formation, new_formation }

// Stat upgraded
`${LEAGUE_PACKAGE_ID}::team_nft::TeamStatUpgraded`
// Fields: { team_id, stat_type, old_value, new_value, cost }

// Stats updated after match
`${LEAGUE_PACKAGE_ID}::team_nft::TeamStatsUpdated`
// Fields: { team_id, wins, losses, draws, goals_for, goals_against }
```

### ai_match_engine Events

```ts
// Match scheduled
`${LEAGUE_PACKAGE_ID}::ai_match_engine::MatchScheduled`
// Fields: { match_id, home_team_id, away_team_id, deadline }

// Match settled
`${LEAGUE_PACKAGE_ID}::ai_match_engine::MatchSettled`
// Fields: { match_id, home_team_id, away_team_id, home_score, away_score, home_possession, away_possession }
```

### betting_pool Events

```ts
// Pool seeded
`${LEAGUE_PACKAGE_ID}::betting_pool::MatchPoolSeeded`
// Fields: { match_id, seed_amount, timestamp }

// Bet placed
`${LEAGUE_PACKAGE_ID}::betting_pool::BetPlaced`
// Fields: { bet_id, bettor, match_id, amount, parlay_multiplier, num_matches }

// Winnings claimed
`${LEAGUE_PACKAGE_ID}::betting_pool::WinningsClaimed`
// Fields: { bet_id, bettor, base_payout, final_payout, parlay_multiplier }

// Bet lost
`${LEAGUE_PACKAGE_ID}::betting_pool::BetLost`
// Fields: { bet_id, bettor }

// Revenue finalized
`${LEAGUE_PACKAGE_ID}::betting_pool::MatchRevenueFinal`
// Fields: { match_id, profit_to_lp, loss_from_lp, season_share }
```

**Querying events example:**

```ts
// Get recent match settlements
const events = await suiClient.queryEvents({
  query: {
    MoveEventType: `${LEAGUE_PACKAGE_ID}::ai_match_engine::MatchSettled`,
  },
  limit: 20,
  order: 'descending',
});

// Get user's bets
const betEvents = await suiClient.queryEvents({
  query: {
    MoveEventType: `${LEAGUE_PACKAGE_ID}::betting_pool::BetPlaced`,
  },
  limit: 50,
  order: 'descending',
});
// Filter client-side for bettor === userAddress
```

---

## Error Codes

### team_nft

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `E_INVALID_STAT` | Stat out of range (1-100) |
| 1 | `E_STAT_EXCEEDS_TOTAL` | atk+def+mid > 150 |
| 2 | `E_INVALID_FORMATION` | Formation not 1-5 |
| 3 | `E_INVALID_STRATEGY` | Strategy not 1-6 |
| 4 | `E_NOT_OWNER` | Caller is not team owner |
| 5 | `E_INSUFFICIENT_PAYMENT` | Not enough OCT |
| 6 | `E_STAT_AT_MAX` | Stat already at 100 |
| 8 | `E_STRATEGY_LOCKED` | Strategy changed within last hour |

### ai_match_engine

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `E_MATCH_NOT_SCHEDULED` | Match result not available |
| 1 | `E_MATCH_ALREADY_SETTLED` | Already settled |
| 2 | `E_DEADLINE_NOT_REACHED` | Cannot settle yet |
| 3 | `E_SAME_TEAM` | Cannot play against self |

### betting_pool

| Code | Constant | Meaning |
|------|----------|---------|
| 0 | `E_NOT_ADMIN` | Caller is not admin |
| 2 | `E_POOL_NOT_SEEDED` | Match pool not seeded |
| 3 | `E_MATCH_NOT_SETTLED` | Match not settled yet |
| 4 | `E_BET_TOO_LARGE` | Bet > 10,000 OCT |
| 5 | `E_INSUFFICIENT_PAYMENT` | Not enough OCT |
| 6 | `E_ALREADY_CLAIMED` | Already claimed winnings |
| 7 | `E_NOT_BETTOR` | Caller is not bet owner |
| 8 | `E_INVALID_MATCH_COUNT` | Invalid parlay (deprecated) |
| 9 | `E_INVALID_OUTCOME` | Outcome not 1-3 |
| 10 | `E_PAYOUT_CAP_REACHED` | Match payout limit hit |
| 11 | `E_INSUFFICIENT_LIQUIDITY` | Not enough in escrow/vault |
| 12 | `E_MATCH_ALREADY_SEEDED` | Match seeded twice |
| 13 | `E_MATCH_ID_MISMATCH` | Bet/accounting/match ID mismatch |

---

## Frontend Checklist

- [ ] Deploy package, save all shared object IDs
- [ ] Update constants with deployed IDs
- [ ] Test `create_team` flow end-to-end
- [ ] Test `add_liquidity` / `remove_liquidity` flow
- [ ] Test full match lifecycle: schedule → seed → bet → settle → claim → finalize
- [ ] Display locked odds before bet placement
- [ ] Show strategy lock countdown timer (1 hour after change)
- [ ] Show momentum indicator (last 5 results with W/L/D badges)
- [ ] Show formation-strategy synergy indicator in team editor
- [ ] Handle `E_STRATEGY_LOCKED` error with user-friendly message
- [ ] Handle `E_MATCH_ALREADY_SEEDED` on admin panel
- [ ] Index events for activity feed
- [ ] Poll `ScheduledMatch` for settlement status
- [ ] Show escrow balance on match pool page
