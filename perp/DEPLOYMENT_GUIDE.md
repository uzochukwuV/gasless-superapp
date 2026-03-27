# Perpetual Trading Platform - Deployment Guide

## 🎯 Overview

Your perpetual trading platform now includes **7 comprehensive user acquisition modules** that create a viral, engaging ecosystem to attract and retain traders.

---

## 📦 New Modules Created

### Core User Acquisition Features:

1. **[perp_rewards.move](sources/perp_rewards.move)** - Early adopter bonuses, volume rewards, profit sharing
2. **[perp_referrals.move](sources/perp_referrals.move)** - 2-tier referral system with rewards
3. **[perp_achievements.move](sources/perp_achievements.move)** - NFT achievement badges (15 types)
4. **[perp_fee_tiers.move](sources/perp_fee_tiers.move)** - Volume-based fee discounts (4 tiers)
5. **[perp_competitions.move](sources/perp_competitions.move)** - Weekly/monthly trading contests
6. **[perp_social.move](sources/perp_social.move)** - Social trading rewards (share, like, copy)
7. **[perp_protection.move](sources/perp_protection.move)** - First trade loss protection

### Testing:

8. **[tests/perp_promotional_tests.move](tests/perp_promotional_tests.move)** - Comprehensive tests for all features

### Documentation:

9. **[USER_ACQUISITION_GUIDE.md](USER_ACQUISITION_GUIDE.md)** - Complete feature documentation

---

## 🚀 Deployment Steps

### Phase 1: Build and Deploy Contracts

```bash
# Navigate to perp directory
cd /home/uzo/my_directory/gasless-superapp/perp

# Build the project
sui move build

# Deploy to testnet (replace with your network)
sui client publish --gas-budget 500000000
```

**Save the following Object IDs after deployment:**
- `LiquidityPool` ID
- `PriceFeed` ID
- `RewardsPool` ID
- `ReferralSystem` ID
- `AchievementTracker` ID
- `FeeTierSystem` ID
- `CompetitionManager` ID
- `SocialTradingSystem` ID
- `LossProtectionSystem` ID

---

### Phase 2: Fund Reward Pools

After deployment, fund all promotional pools:

```bash
# Fund Rewards Pool (1,000,000 OCT recommended)
sui client call \
  --package <PACKAGE_ID> \
  --module perp_rewards \
  --function fund_rewards_pool \
  --args <REWARDS_POOL_ID> <COIN_OBJECT_ID> 1000000000000000 \
  --gas-budget 10000000

# Fund Referral Pool (250,000 OCT recommended)
sui client call \
  --package <PACKAGE_ID> \
  --module perp_referrals \
  --function fund_referral_pool \
  --args <REFERRAL_SYSTEM_ID> <COIN_OBJECT_ID> 250000000000000 \
  --gas-budget 10000000

# Fund Competition Pool (100,000 OCT recommended)
sui client call \
  --package <PACKAGE_ID> \
  --module perp_competitions \
  --function fund_prize_pool \
  --args <COMPETITION_MANAGER_ID> <COIN_OBJECT_ID> 100000000000000 \
  --gas-budget 10000000

# Fund Social Pool (50,000 OCT recommended)
sui client call \
  --package <PACKAGE_ID> \
  --module perp_social \
  --function fund_social_pool \
  --args <SOCIAL_SYSTEM_ID> <COIN_OBJECT_ID> 50000000000000 \
  --gas-budget 10000000

# Fund Protection Pool (500,000 OCT recommended)
sui client call \
  --package <PACKAGE_ID> \
  --module perp_protection \
  --function fund_protection_pool \
  --args <PROTECTION_SYSTEM_ID> <COIN_OBJECT_ID> 500000000000000 \
  --gas-budget 10000000
```

**Total Funding Required: ~2,000,000 OCT**

---

### Phase 3: Create First Competition

```bash
# Create a weekly volume competition
sui client call \
  --package <PACKAGE_ID> \
  --module perp_competitions \
  --function create_competition \
  --args <COMPETITION_MANAGER_ID> \
    "Launch Week Volume Contest" \
    1 \
    604800000 \
    10000000000000 \
    <CLOCK_ID> \
  --gas-budget 10000000
```

**Competition Types:**
- `1` = Volume Competition
- `2` = PnL Competition
- `3` = Win Rate Competition
- `4` = Consistency Competition

---

## 🔧 Integration with Main Contract

You'll need to update [perp.move](sources/perp.move) to call the promotional modules. Here's a template:

### Add Module Imports

```move
use perp::perp_rewards;
use perp::perp_referrals;
use perp::perp_achievements;
use perp::perp_fee_tiers;
use perp::perp_competitions;
use perp::perp_social;
use perp::perp_protection;
```

### Update `open_position` Function

```move
public entry fun open_position(
    pool: &mut LiquidityPool,
    mut collateral_payment: Coin<OCT>,
    leverage: u64,
    is_long: bool,
    price_feed: &PriceFeed,
    clock: &Clock,
    // Add promotional system parameters
    achievements: &mut AchievementTracker,
    fee_tiers: &mut FeeTierSystem,
    rewards: &mut RewardsPool,
    ctx: &mut TxContext
) {
    let trader = tx_context::sender(ctx);

    // ... existing code ...

    // Apply fee discount from tier system
    let base_opening_fee = perp_fees::calculate_opening_fee(position_size);
    let discounted_fee = perp_fee_tiers::get_discounted_fee(
        fee_tiers,
        trader,
        base_opening_fee
    );

    // Use discounted_fee instead of opening_fee
    // ... rest of position opening logic ...

    // Update user tier
    perp_fee_tiers::update_user_tier(fee_tiers, trader, position_size, ctx);

    // Record volume for rewards
    perp_rewards::record_trade_volume(rewards, trader, position_size, ctx);

    // Track achievements
    perp_achievements::update_trade_stats(
        achievements,
        trader,
        position_size,
        false, // Don't know if win yet
        leverage,
        ctx
    );
}
```

### Update `close_position` Function

```move
public entry fun close_position(
    pool: &mut LiquidityPool,
    position: Position,
    price_feed: &PriceFeed,
    clock: &Clock,
    // Add promotional systems
    achievements: &mut AchievementTracker,
    protection: &mut LossProtectionSystem,
    referrals: &mut ReferralSystem,
    ctx: &mut TxContext
) {
    let trader = tx_context::sender(ctx);

    // ... existing close logic ...

    // Check if first trade with loss - activate protection
    let is_first_trade = check_if_first_trade(trader); // Implement this
    if (!is_profit && is_first_trade) {
        if (perp_protection::is_eligible_for_protection(protection, trader, true)) {
            perp_protection::activate_protection(
                protection,
                trader,
                pnl, // loss amount
                true,
                ctx
            );
        };
    };

    // Update achievement stats
    perp_achievements::update_trade_stats(
        achievements,
        trader,
        position_size,
        is_profit,
        leverage,
        ctx
    );

    // Process referral rewards on fees paid
    perp_referrals::process_referral_rewards(
        referrals,
        trader,
        total_fees,
        ctx
    );
}
```

---

## 📊 Testing

Run the comprehensive test suite:

```bash
# Test promotional features
sui move test --filter perp_promotional_tests

# Test specific modules
sui move test --filter test_referral
sui move test --filter test_early_adopter
sui move test --filter test_achievement
sui move test --filter test_fee_tier
sui move test --filter test_competition
sui move test --filter test_social
sui move test --filter test_protection

# Run all tests
sui move test
```

---

## 🎮 User Flow Examples

### Example 1: New User Journey

```bash
# 1. User claims early adopter bonus
sui client call \
  --function claim_early_adopter_bonus \
  --args <REWARDS_POOL_ID>

# 2. User creates referral code
sui client call \
  --function create_referral_code \
  --args <REFERRAL_SYSTEM_ID> "MY_CODE"

# 3. User opens first trade (automatically protected)
# ... trade execution ...

# 4. If loss occurs, protection activates automatically

# 5. User claims accumulated rewards
sui client call \
  --function claim_rewards \
  --args <REWARDS_POOL_ID>
```

### Example 2: Referral Usage

```bash
# New user uses referral code
sui client call \
  --function use_referral_code \
  --args <REFERRAL_SYSTEM_ID> "FRIEND_CODE"

# Referrer earns rewards automatically when referee trades
# Referrer claims rewards
sui client call \
  --function claim_referral_rewards \
  --args <REFERRAL_SYSTEM_ID>
```

### Example 3: Social Trading

```bash
# User shares winning trade
sui client call \
  --function share_trade \
  --args <SOCIAL_SYSTEM_ID> \
    1000000000000 \
    10 \
    true \
    1000000 \
    1100000 \
    100000000000 \
    "My winning strategy!"

# Other users like the trade
sui client call \
  --function like_trade \
  --args <SOCIAL_SYSTEM_ID> <TRADE_ID>

# Claim social rewards
sui client call \
  --function claim_social_rewards \
  --args <SOCIAL_SYSTEM_ID>
```

---

## 📈 Monitoring & Analytics

### Key Metrics to Track:

1. **User Acquisition:**
   - Early adopter claim rate
   - Referral conversion rate
   - First trade protection usage

2. **Engagement:**
   - Average trades per user
   - Achievement unlock rate
   - Social share frequency
   - Competition participation

3. **Retention:**
   - Fee tier progression
   - Repeat competition entries
   - Active referrers count

4. **Financial:**
   - Total rewards distributed
   - Average fee discount applied
   - ROI on promotional spend

### Query Functions:

```typescript
// Get user stats
const rewardStats = await provider.call({
  target: `${packageId}::perp_rewards::get_user_rewards`,
  arguments: [rewardsPoolId, userAddress]
});

const referralStats = await provider.call({
  target: `${packageId}::perp_referrals::get_referral_stats`,
  arguments: [referralSystemId, userAddress]
});

const achievementStats = await provider.call({
  target: `${packageId}::perp_achievements::get_user_stats`,
  arguments: [achievementTrackerId, userAddress]
});

const tierInfo = await provider.call({
  target: `${packageId}::perp_fee_tiers::get_user_tier_info`,
  arguments: [feeTierSystemId, userAddress]
});
```

---

## 🎯 Marketing Campaign Ideas

### Launch Week Campaign

**"First 1,000 Get 100 OCT Free + Risk-Free Trading"**

1. **Week 1-2**: Pre-registration
   - Collect emails
   - Create referral codes early
   - Build anticipation

2. **Launch Day**:
   - Early adopter bonus claims open
   - First trade protection active
   - Launch competition starts

3. **Week 1**:
   - Daily profit sharing draws
   - Social sharing campaign
   - Referral leaderboard

4. **Month 1**:
   - First monthly competition
   - Tier upgrade announcements
   - Achievement showcase

### Social Media Strategy

**Twitter/X Campaign:**
```
🚀 Trade perpetuals with ZERO risk on your first trade!

✅ 100% loss protection (up to 100 OCT)
✅ First 1,000 users get 100 OCT FREE
✅ Earn from referrals forever
✅ Collect rare NFT achievements

Join now: [link]
Use code: [referral_code]

#DeFi #Perpetuals #CryptoTrading
```

**Community Incentives:**
- Share profitable trades → Earn rewards
- Hit 100 likes → 10 OCT viral bonus
- Top 3 in weekly competition → Cash prizes
- Refer 10 friends → 1,000 OCT bonus

---

## 🔒 Security Considerations

### Admin Controls

Only admin can:
- Pause protocol
- Create competitions
- Distribute competition prizes
- Fund reward pools

### Safety Features

1. **Circuit Breaker**: Max 10% price change per update
2. **Position Limits**: Max 10% of pool per position
3. **Max Leverage**: Capped at 50x
4. **Protection Caps**: Max 100 OCT per user, 10,000 users total
5. **Daily Limits**: Max 10 social shares per day

### Audit Recommendations

Before mainnet:
- [ ] Professional smart contract audit
- [ ] Economic model review
- [ ] Stress testing with high volume
- [ ] Gas optimization
- [ ] Front-end security review

---

## 💡 Future Enhancements

### Phase 2 Features (Optional):

1. **Copy Trading System**
   - Follow top traders automatically
   - Portfolio allocation
   - Performance tracking

2. **Staking Rewards**
   - Stake OLP tokens for rewards
   - Boosted fee discounts
   - Governance rights

3. **Cross-Chain Integration**
   - Bridge to other chains
   - Multi-asset perpetuals
   - Cross-chain competitions

4. **Advanced Analytics**
   - Trading performance dashboard
   - AI-powered insights
   - Risk metrics

5. **Mobile App**
   - Push notifications for competitions
   - Easy social sharing
   - Achievement gallery

---

## 📞 Support & Resources

### Documentation
- [USER_ACQUISITION_GUIDE.md](USER_ACQUISITION_GUIDE.md) - Complete feature guide
- [perp_tests.move](tests/perp_tests.move) - Core trading tests
- [perp_promotional_tests.move](tests/perp_promotional_tests.move) - Promotional feature tests

### Module Addresses
After deployment, update your frontend with:
```javascript
export const CONTRACTS = {
  PACKAGE_ID: "0x...",
  LIQUIDITY_POOL: "0x...",
  PRICE_FEED: "0x...",
  REWARDS_POOL: "0x...",
  REFERRAL_SYSTEM: "0x...",
  ACHIEVEMENT_TRACKER: "0x...",
  FEE_TIER_SYSTEM: "0x...",
  COMPETITION_MANAGER: "0x...",
  SOCIAL_SYSTEM: "0x...",
  PROTECTION_SYSTEM: "0x..."
};
```

---

## ✅ Pre-Launch Checklist

- [ ] All modules compiled successfully
- [ ] All tests passing
- [ ] Contracts deployed to testnet
- [ ] All reward pools funded
- [ ] First competition created
- [ ] Admin controls verified
- [ ] Circuit breakers tested
- [ ] Frontend integration complete
- [ ] Analytics dashboard ready
- [ ] Marketing materials prepared
- [ ] Community channels set up
- [ ] Documentation published
- [ ] Security audit completed (recommended)
- [ ] Mainnet deployment plan ready

---

## 🎊 Launch Metrics

**Expected First Month:**
- 1,000+ early adopters
- 5,000+ total users (with viral referrals)
- 10,000+ trades executed
- 500+ achievements unlocked
- 2,000+ social shares
- 100+ competition participants

**Budget Allocation (2M OCT):**
- Early Adopter Bonuses: 100,000 OCT (1,000 × 100)
- Referral Rewards: 250,000 OCT
- Loss Protection: 500,000 OCT
- Competitions: 100,000 OCT
- Social Rewards: 50,000 OCT
- Volume Rewards: 1,000,000 OCT
- **Reserve Buffer**: Plan for growth

---

## 🚀 Ready to Launch!

Your perpetual trading platform now has:
✅ **Viral referral system**
✅ **Risk-free onboarding**
✅ **Gamified achievements**
✅ **Competitive trading**
✅ **Social engagement**
✅ **Loyalty rewards**
✅ **Fee optimization**

**All the tools you need to attract and retain users in a competitive DeFi market.**

Good luck with your launch! 🎉
