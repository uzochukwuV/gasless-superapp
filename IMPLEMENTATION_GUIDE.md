# One Chain Sports Betting Implementation Guide

## Quick Start Summary

This guide provides step-by-step instructions for building and deploying the League One sports betting platform on One Chain.

---

## Project Structure

```
gasless-superapp/
├── leaguealpha/              # Original Ethereum contracts (reference)
│   ├── Gmae.sol             # GameEngine with Chainlink VRF
│   └── Pool.sol             # BettingPool with fixed odds
│
├── league_one/               # NEW: One Chain implementation
│   ├── Move.toml
│   └── sources/
│       ├── game_engine.move      # Match generation with native randomness
│       └── betting_pool.move     # Betting pool with fixed odds
│
├── ONECHAIN_SPORTS_BETTING_ARCHITECTURE.md  # Detailed architecture
└── IMPLEMENTATION_GUIDE.md                   # This file
```

---

## Phase 1: Setup Development Environment

### 1.1 Install One Chain CLI

```bash
# Install One CLI (similar to Sui CLI)
curl https://one.chain/install.sh | sh

# Verify installation
one --version

# Create new wallet
one client new-address ed25519
```

### 1.2 Initialize Move Project

```bash
cd gasless-superapp
mkdir league_one
cd league_one

# Initialize Move project
one move new league_one
cd league_one
```

### 1.3 Configure Move.toml

```toml
[package]
name = "league_one"
version = "0.1.0"
edition = "2024"

[dependencies]
One = { git = "https://github.com/onechain/one", subdir = "crates/one-framework/packages/one-framework", rev = "framework/mainnet" }

[addresses]
league_one = "0x0"
one = "0x2"
```

---

## Phase 2: Core Module Development

### 2.1 Game Engine Module (✅ Complete)

**File**: `league_one/sources/game_engine.move`

**Key Features**:
- ✅ Native randomness using `one::random` (NO Chainlink VRF needed!)
- ✅ 20 teams, 36 rounds, 10 matches per round
- ✅ Season and round management
- ✅ Fisher-Yates shuffle for team pairings
- ✅ Realistic score generation (0-5 goals, weighted probabilities)
- ✅ Team standings tracking

**Testing**:
```bash
# Build module
one move build

# Run tests
one move test

# Test specific function
one move test game_engine::test_score_generation
```

**Deploy to Testnet**:
```bash
# Publish module
one client publish --gas-budget 100000000

# Save package ID
export GAME_ENGINE_PACKAGE=<package_id>
```

### 2.2 Betting Pool Module (✅ Complete)

**File**: `league_one/sources/betting_pool.move`

**Key Features**:
- ✅ Fixed odds model (odds locked at seeding)
- ✅ Unified LP pool architecture
- ✅ 5% protocol fee
- ✅ Parlay system (1.05x-1.25x multipliers)
- ✅ Seeding: 30,000 OCT per round
- ✅ Odds compression (1.3x-1.7x range)
- ✅ Risk caps (max bet, max payout, round limits)

**Testing**:
```bash
# Test odds calculation
one move test betting_pool::test_compress_odds

# Test bet placement
one move test betting_pool::test_place_bet

# Test payout calculation
one move test betting_pool::test_calculate_payout
```

---

## Phase 3: Smart Contract Interactions

### 3.1 Start a Season

```bash
# Call start_season on GameState
one client call \
  --package $GAME_ENGINE_PACKAGE \
  --module game_engine \
  --function start_season \
  --args $GAME_STATE_ID "0x6" \
  --gas-budget 10000000
```

### 3.2 Start a Round

```bash
# Call start_round (requires Random object at 0x8)
one client call \
  --package $GAME_ENGINE_PACKAGE \
  --module game_engine \
  --function start_round \
  --args $GAME_STATE_ID $SEASON_ID "0x8" "0x6" \
  --gas-budget 20000000
```

### 3.3 Seed Betting Pools

```bash
# Seed round with 30,000 OCT
one client call \
  --package $BETTING_POOL_PACKAGE \
  --module betting_pool \
  --function seed_round \
  --args $VAULT_ID $ROUND_ID $ROUND_NUMBER "0x6" \
  --gas-budget 15000000
```

### 3.4 Place a Bet

```bash
# Place 100 OCT bet on matches 0,1,2 (outcomes: HOME, AWAY, DRAW)
one client call \
  --package $BETTING_POOL_PACKAGE \
  --module betting_pool \
  --function place_bet \
  --args $ACCOUNTING_ID $VAULT_ID "[0,1,2]" "[1,2,3]" "100000000000" "0x6" \
  --gas-budget 10000000
```

### 3.5 Settle Round

```bash
# First settle in game_engine
one client call \
  --package $GAME_ENGINE_PACKAGE \
  --module game_engine \
  --function settle_round \
  --args $ROUND_ID $SEASON_ID $STANDINGS_ID "0x8" "0x6" \
  --gas-budget 30000000

# Then settle in betting_pool
one client call \
  --package $BETTING_POOL_PACKAGE \
  --module betting_pool \
  --function settle_round \
  --args $ACCOUNTING_ID $ROUND_ID \
  --gas-budget 10000000
```

### 3.6 Claim Winnings

```bash
# Claim winnings for a bet
one client call \
  --package $BETTING_POOL_PACKAGE \
  --module betting_pool \
  --function claim_winnings \
  --args $BET_ID $ACCOUNTING_ID $VAULT_ID $ROUND_ID \
  --gas-budget 10000000
```

---

## Phase 4: Frontend Integration

### 4.1 Setup TypeScript SDK

```bash
npm install @mysten/sui.js @mysten/dapp-kit
```

### 4.2 Connect to One Chain

```typescript
import { getFullnodeUrl, SuiClient } from '@mysten/sui.js/client';

const client = new SuiClient({
  url: getFullnodeUrl('testnet')
});

// Get game state
const gameState = await client.getObject({
  id: GAME_STATE_ID,
  options: { showContent: true }
});
```

### 4.3 Display Live Odds

```typescript
// Fetch locked odds for a match
const { data } = await client.getDynamicFieldObject({
  parentId: ROUND_ACCOUNTING_ID,
  name: {
    type: 'u64',
    value: matchIndex.toString()
  }
});

const odds = data.content.fields.value;
console.log('Home odds:', odds.home_odds / 1e18);
console.log('Away odds:', odds.away_odds / 1e18);
console.log('Draw odds:', odds.draw_odds / 1e18);
```

### 4.4 Place Bet from Frontend

```typescript
import { TransactionBlock } from '@mysten/sui.js/transactions';

const tx = new TransactionBlock();

// Split coin for bet amount
const [betCoin] = tx.splitCoins(tx.gas, [tx.pure(100_000_000_000)]); // 100 OCT

tx.moveCall({
  target: `${PACKAGE_ID}::betting_pool::place_bet`,
  arguments: [
    tx.object(ACCOUNTING_ID),
    tx.object(VAULT_ID),
    tx.pure([0, 1, 2]), // match indices
    tx.pure([1, 2, 3]), // outcomes
    betCoin,
    tx.object('0x6') // Clock
  ],
});

const result = await client.signAndExecuteTransactionBlock({
  transactionBlock: tx,
  signer: wallet
});
```

### 4.5 Subscribe to Events

```typescript
// Listen for bet placed events
const unsubscribe = await client.subscribeEvent({
  filter: {
    Package: PACKAGE_ID,
    Module: 'betting_pool',
    EventType: 'BetPlaced'
  },
  onMessage: (event) => {
    console.log('New bet:', event.parsedJson);
    // Update UI with new bet
  }
});
```

---

## Phase 5: Automated Operations (Backend)

### 5.1 Automated Round Settlement

```typescript
// Cron job running every 3 hours
import { CronJob } from 'cron';

const settlementJob = new CronJob('0 */3 * * *', async () => {
  // Check if round deadline passed
  const round = await getRoundData(currentRoundId);
  const now = Date.now();

  if (now >= round.deadline && !round.settled) {
    // Settle round
    await settleRound(currentRoundId);
    console.log(`Round ${currentRoundId} settled`);

    // Start next round
    await startNextRound(currentSeasonId);
  }
});

settlementJob.start();
```

### 5.2 LP Pool Management

```typescript
// Monitor LP pool health
async function monitorLPPool() {
  const vault = await client.getObject({
    id: VAULT_ID,
    options: { showContent: true }
  });

  const balance = vault.data.content.fields.balance;
  const lockedReserves = vault.data.content.fields.lp_borrowed;

  // Alert if liquidity low
  if (balance < MIN_LIQUIDITY_THRESHOLD) {
    console.warn('LOW LIQUIDITY WARNING');
    // Trigger LP incentives
  }

  // Alert if too much locked
  const utilizationRate = lockedReserves / balance;
  if (utilizationRate > 0.8) {
    console.warn('HIGH UTILIZATION WARNING');
    // Reduce max bet limits
  }
}

setInterval(monitorLPPool, 60000); // Every minute
```

---

## Phase 6: Testing & Auditing

### 6.1 Unit Tests

Create comprehensive test suite:

```move
// league_one/tests/game_engine_tests.move

#[test_only]
module league_one::game_engine_tests {
    use league_one::game_engine;
    use one::test_scenario::{Self as ts};
    use one::random;
    use one::clock;

    #[test]
    fun test_season_creation() {
        let mut scenario = ts::begin(@0xA);

        // Initialize game
        {
            let ctx = ts::ctx(&mut scenario);
            game_engine::init(ctx);
        };

        ts::next_tx(&mut scenario, @0xA);

        // Start season
        {
            let mut game_state = ts::take_shared<game_engine::GameState>(&scenario);
            let clock_obj = clock::create_for_testing(ts::ctx(&mut scenario));

            game_engine::start_season(
                &mut game_state,
                &clock_obj,
                ts::ctx(&mut scenario)
            );

            assert!(game_engine::get_current_season_id(&game_state) == 1, 0);

            clock::destroy_for_testing(clock_obj);
            ts::return_shared(game_state);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_random_score_generation() {
        // Test score distribution
        let mut scenario = ts::begin(@0xA);

        let random_obj = random::create_for_testing(ts::ctx(&mut scenario));
        let mut generator = random::new_generator(&random_obj, ts::ctx(&mut scenario));

        // Generate 1000 scores
        let mut counts = vector::empty<u64>();
        let mut i = 0;
        while (i < 7) {
            vector::push_back(&mut counts, 0);
            i = i + 1;
        };

        let mut i = 0;
        while (i < 1000) {
            let score = game_engine::score_from_random(&mut generator);
            let count = vector::borrow_mut(&mut counts, (score as u64));
            *count = *count + 1;
            i = i + 1;
        };

        // Verify distribution roughly matches expectations
        // 0: ~15%, 1: ~25%, 2: ~25%, 3: ~17%, 4: ~11%, 5: ~7%
        assert!(*vector::borrow(&counts, 0) > 100, 0); // At least 10%
        assert!(*vector::borrow(&counts, 1) > 200, 1); // At least 20%

        random::destroy_for_testing(random_obj);
        ts::end(scenario);
    }
}
```

### 6.2 Integration Tests

```move
// Test full betting flow
#[test]
fun test_full_betting_flow() {
    let mut scenario = ts::begin(@0xADMIN);

    // 1. Initialize modules
    game_engine::init(ts::ctx(&mut scenario));
    betting_pool::init(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, @0xADMIN);

    // 2. Start season
    {
        let mut game_state = ts::take_shared<game_engine::GameState>(&scenario);
        let clock_obj = clock::create_for_testing(ts::ctx(&mut scenario));
        game_engine::start_season(&mut game_state, &clock_obj, ts::ctx(&mut scenario));
        clock::destroy_for_testing(clock_obj);
        ts::return_shared(game_state);
    };

    // 3. Start round
    // 4. Seed pools
    // 5. Place bets
    // 6. Settle round
    // 7. Claim winnings

    ts::end(scenario);
}
```

### 6.3 Security Audit Checklist

- [ ] **Randomness Security**: Verify `one::random` cannot be manipulated
- [ ] **Reentrancy**: Check all balance updates follow Checks-Effects-Interactions
- [ ] **Integer Overflow**: Verify all math operations are safe
- [ ] **Access Control**: Verify admin functions properly gated
- [ ] **Odds Manipulation**: Verify odds locked and cannot be changed
- [ ] **LP Drain**: Verify caps prevent catastrophic payouts
- [ ] **Front-running**: Verify fixed odds prevent MEV
- [ ] **Timestamp Dependence**: Verify clock usage is safe

---

## Phase 7: Deployment

### 7.1 Testnet Deployment

```bash
# Connect to testnet
one client switch --env testnet

# Fund deployer wallet
one client faucet

# Build and publish
one move build
one client publish --gas-budget 200000000

# Save deployed addresses
export GAME_ENGINE_PACKAGE=<package_id>
export BETTING_POOL_PACKAGE=<package_id>
export GAME_STATE_ID=<object_id>
export VAULT_ID=<object_id>
```

### 7.2 Mainnet Deployment

```bash
# Connect to mainnet
one client switch --env mainnet

# Verify bytecode matches testnet
one move build --fetch-deps-only
diff -r build/league_one testnet_build/

# Deploy with larger gas budget
one client publish --gas-budget 500000000

# Verify deployment
one client object $GAME_STATE_ID
```

### 7.3 Initialize Liquidity Pool

```bash
# Deposit initial liquidity (e.g., 1M OCT)
one client call \
  --package $BETTING_POOL_PACKAGE \
  --module betting_pool \
  --function deposit_liquidity \
  --args $VAULT_ID "1000000000000000" \
  --gas-budget 10000000
```

---

## Phase 8: Monitoring & Maintenance

### 8.1 Key Metrics to Track

```typescript
interface SystemMetrics {
  // Game metrics
  currentSeasonId: number;
  currentRoundId: number;
  totalMatches: number;

  // Betting metrics
  totalBetsPlaced: number;
  totalVolume: bigint;
  totalPayouts: bigint;
  activeRounds: number;

  // LP metrics
  totalLPBalance: bigint;
  totalLPBorrowed: bigint;
  utilizationRate: number;
  lpProfit: bigint;

  // Protocol metrics
  protocolFeesCollected: bigint;
  seasonRewardPool: bigint;
}
```

### 8.2 Alert System

```typescript
// Set up alerts for critical events
const alerts = {
  LOW_LIQUIDITY: 100_000_000_000_000n, // 100k OCT
  HIGH_UTILIZATION: 0.9, // 90%
  LARGE_BET: 5_000_000_000_000n, // 5k OCT
  SETTLEMENT_DELAY: 3_600_000, // 1 hour past deadline
};

async function checkAlerts() {
  const metrics = await getSystemMetrics();

  if (metrics.totalLPBalance < alerts.LOW_LIQUIDITY) {
    sendAlert('LOW_LIQUIDITY', metrics);
  }

  if (metrics.utilizationRate > alerts.HIGH_UTILIZATION) {
    sendAlert('HIGH_UTILIZATION', metrics);
  }
}
```

---

## Comparison: Ethereum vs One Chain

| Feature | Ethereum (Solidity) | One Chain (Move) |
|---------|-------------------|------------------|
| **Randomness** | Chainlink VRF (~$5-10 per call) | Native `one::random` (free) |
| **Settlement Time** | 3+ blocks (~45s) + VRF delay | Instant (same tx) |
| **Gas Costs** | High (~$50-200 per season) | Low (~$1-5 per season) |
| **Safety** | Reentrancy guards needed | Move prevents reentrancy |
| **Token Handling** | ERC20 approve/transferFrom | Native `Coin<T>` safety |
| **State Model** | Contract storage | Object-oriented |
| **Finality** | ~15 minutes | ~2 seconds |

---

## Troubleshooting

### Issue: "Insufficient LP Liquidity"

**Cause**: LP vault balance too low to cover potential payouts

**Fix**:
```bash
# Deposit more liquidity
one client call \
  --package $BETTING_POOL_PACKAGE \
  --module betting_pool \
  --function deposit_liquidity \
  --args $VAULT_ID "500000000000000" \
  --gas-budget 10000000
```

### Issue: "Round Not Settled"

**Cause**: Round deadline not reached or settlement failed

**Fix**:
```bash
# Check round deadline
one client object $ROUND_ID

# If past deadline, manually trigger settlement
one client call \
  --package $GAME_ENGINE_PACKAGE \
  --module game_engine \
  --function settle_round \
  --args $ROUND_ID $SEASON_ID $STANDINGS_ID "0x8" "0x6" \
  --gas-budget 30000000
```

### Issue: "Odds Not Locked"

**Cause**: Round not seeded yet

**Fix**:
```bash
# Seed the round first
one client call \
  --package $BETTING_POOL_PACKAGE \
  --module betting_pool \
  --function seed_round \
  --args $VAULT_ID $ROUND_ID $ROUND_NUMBER "0x6" \
  --gas-budget 15000000
```

---

## Next Steps

1. **Complete Module Testing**: Run comprehensive test suite
2. **Deploy to Testnet**: Test in live environment
3. **Build Frontend**: Create React/Next.js UI
4. **Add Analytics**: Track metrics and user behavior
5. **Security Audit**: Professional audit before mainnet
6. **Community Testing**: Beta test with real users
7. **Mainnet Launch**: Deploy to production
8. **Marketing**: Promote to One Chain community

---

## Resources

- **One Chain Docs**: https://docs.onechain.io
- **Move Book**: https://move-language.github.io/move/
- **Example DApps**: https://github.com/onechain/examples
- **Discord**: https://discord.gg/onechain
- **GitHub**: https://github.com/onechain/one

---

## Support

For questions or issues:
- GitHub Issues: https://github.com/yourusername/league_one/issues
- Discord: #dev-support channel
- Email: dev@leagueone.io

## License

MIT License - See LICENSE file for details
