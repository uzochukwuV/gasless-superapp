# Perpetual Trading Platform - User Acquisition Features

## Overview
This document outlines the comprehensive user acquisition and retention features implemented for your perpetual trading platform.

---

## 🎁 Feature Summary

### 1. **Referral System** ([perp_referrals.move](sources/perp_referrals.move))

**Viral Growth Mechanism**

#### Rewards Structure:
- **Tier 1 (Direct Referrals)**: 10% of referee's trading fees
- **Tier 2 (Indirect Referrals)**: 2% of tier 2 referee's fees
- **Referee Benefits**: 5% fee discount on all trades
- **Super Referrer Bonus**: 1,000 OCT after 10+ referrals

#### How It Works:
1. Users create custom referral codes
2. Share codes with friends
3. Earn passive income from referrals' trading activity
4. Build 2-tier referral network

#### Key Functions:
```move
// Create referral code
create_referral_code(system, "MY_CODE", ctx)

// Use a referral code
use_referral_code(system, "FRIEND_CODE", ctx)

// Claim referral rewards
claim_referral_rewards(system, ctx)
```

---

### 2. **Early Adopter Bonus** ([perp_rewards.move](sources/perp_rewards.move))

**First-Mover Advantage**

#### Benefits:
- **First 1,000 Users**: 100 OCT instant bonus
- **Exclusive Badge**: Early Adopter achievement NFT
- **Priority Access**: Special competition entry

#### How It Works:
1. User makes first trade
2. Automatically qualifies if within first 1,000
3. Claims bonus via `claim_early_adopter_bonus()`
4. Receives Achievement NFT

---

### 3. **Trading Competitions** ([perp_competitions.move](sources/perp_competitions.move))

**Weekly & Monthly Contests**

#### Competition Types:
1. **Volume Competition**: Highest trading volume
2. **PnL Competition**: Highest profit
3. **Win Rate Competition**: Best win percentage (min 10 trades)
4. **Consistency Competition**: Most stable profits

#### Prize Distribution:
- **1st Place**: 50% of prize pool
- **2nd Place**: 30% of prize pool
- **3rd Place**: 20% of prize pool

#### How It Works:
```move
// Admin creates competition
create_competition(manager, "Weekly Volume", COMPETITION_TYPE_VOLUME, DURATION_WEEKLY, 10000_OCT, clock, ctx)

// Users join
join_competition(manager, competition_id, clock, ctx)

// Admin distributes prizes after competition ends
end_competition(manager, competition_id, first, second, third, clock, ctx)
distribute_prizes(manager, competition_id, ctx)
```

---

### 4. **Fee Discount Tiers** ([perp_fee_tiers.move](sources/perp_fee_tiers.move))

**Volume-Based Rewards**

#### Tier Structure:

| Tier | Volume Required | Base Discount | Final Fee |
|------|----------------|---------------|-----------|
| Bronze | 0 OCT | 0% | 0.1% |
| Silver | 10,000 OCT | 20% | 0.08% |
| Gold | 100,000 OCT | 40% | 0.06% |
| Platinum | 1,000,000 OCT | 60% | 0.04% |

#### Loyalty Bonuses:
- **30 Days Active**: +5% additional discount
- **90 Days Active**: +10% additional discount
- **180 Days Active**: +15% additional discount

#### How It Works:
- Automatically upgraded based on trading volume
- Loyalty bonuses accumulate over time
- Apply to all trading fees

---

### 5. **Social Trading Rewards** ([perp_social.move](sources/perp_social.move))

**Earn By Sharing**

#### Reward Opportunities:
- **Share Profitable Trade**: 0.1 OCT per share (max 10/day)
- **Receive Likes**: 0.01 OCT per like
- **Trade Copied**: 1% of copied volume
- **Viral Bonus**: 10 OCT at 100 likes

#### How It Works:
```move
// Share a winning trade
share_trade(system, position_size, leverage, is_long, entry_price, exit_price, pnl, "My strategy!", ctx)

// Like someone's trade
like_trade(system, trade_id, ctx)

// System records when trades are copied
record_copy_trade(system, trade_id, copier, volume, ctx)

// Claim social rewards
claim_social_rewards(system, ctx)
```

---

### 6. **First Trade Loss Protection** ([perp_protection.move](sources/perp_protection.move))

**Risk-Free First Trade**

#### Protection Details:
- **Coverage**: 100% of first trade loss
- **Maximum**: 100 OCT protection
- **Eligibility**: First 10,000 users
- **One-time Use**: Per user

#### How It Works:
1. User makes first trade
2. If trade results in loss, protection activates automatically
3. User receives compensation up to 100 OCT
4. Can trade with confidence knowing first loss is covered

#### Key Functions:
```move
// Check eligibility
is_eligible_for_protection(system, user, is_first_trade)

// Activate protection after loss (automatic)
activate_protection(system, user, loss_amount, is_first_trade, ctx)
```

---

### 7. **Achievement NFT System** ([perp_achievements.move](sources/perp_achievements.move))

**Gamified Trading Milestones**

#### Achievement Categories:

**Trading Milestones:**
- First Trade (Common)
- First Victory (Common)
- 10 Trades - Apprentice Trader (Common)
- 100 Trades - Veteran Trader (Rare)
- 1,000 Trades - Trading Master (Epic)

**Volume Milestones:**
- 100K OCT Volume - High Roller (Rare)
- 1M OCT Volume - Whale Trader (Epic)
- 10M OCT Volume - Legendary Whale (Legendary)

**Special Achievements:**
- Risk Taker - Used 50x leverage (Rare)
- Diamond Hands - Held position 7+ days (Epic)
- Liquidation Hunter - 10+ liquidations (Epic)
- Early Adopter - First 1,000 users (Legendary)
- Super Referrer - 10+ referrals (Epic)
- Competition Champion - Won competition (Legendary)

#### Rarity Levels:
- **Common**: Basic milestones
- **Rare**: Significant accomplishments
- **Epic**: Major achievements
- **Legendary**: Exclusive elite status

---

### 8. **Volume Rewards** ([perp_rewards.move](sources/perp_rewards.move))

**Continuous Cashback**

#### Reward Rate:
- **0.05%** of every trade volume returned as rewards
- Automatic tracking and accumulation
- Claim anytime

#### Example:
- Trade 10,000 OCT volume → Earn 5 OCT rewards
- Trade 100,000 OCT volume → Earn 50 OCT rewards

---

### 9. **Daily Profit Sharing Events** ([perp_rewards.move](sources/perp_rewards.move))

**Lucky Trader Drawings**

#### How It Works:
- **Daily Prize Pool**: 1,000 OCT
- **Entry Method**: Trade volume above 100 OCT
- **Selection**: Based on trading activity (more volume = more entries)
- **Distribution**: Automatic daily

---

## 📊 User Journey

### New User Flow:

1. **Sign Up** → Receive referral code invitation
2. **Use Referral Code** → Get 5% fee discount
3. **Claim Early Adopter Bonus** → 100 OCT (if within first 1,000)
4. **Make First Trade** → Protected against loss (up to 100 OCT)
5. **First Trade Achievement NFT** → Unlock "First Trade" badge
6. **Join Competition** → Enter weekly trading contest
7. **Share Profitable Trade** → Earn social rewards
8. **Reach Silver Tier** → 20% fee discount at 10K volume
9. **Refer Friends** → Earn passive referral income
10. **Unlock More Achievements** → Collect rare NFTs

### Engaged User Benefits:

- **Volume Rewards**: 0.05% cashback on all trades
- **Fee Discounts**: Up to 60% lower fees (Platinum tier)
- **Referral Income**: Passive earnings from referrals
- **Social Rewards**: Earn from sharing trades
- **Competition Prizes**: Weekly/monthly prize pools
- **Achievement NFTs**: Collectible status symbols
- **Loyalty Bonuses**: Additional discounts over time

---

## 💰 Revenue vs Incentive Balance

### Revenue Sources:
1. Trading fees (0.1% opening/closing)
2. Borrowing fees (0.01%/hour)
3. Liquidation fees (5%)

### User Incentives:
1. Referral rewards (funded separately)
2. Early adopter bonuses (one-time)
3. Competition prizes (scheduled pools)
4. Social rewards (marketing budget)
5. Loss protection (risk management fund)
6. Volume rewards (fee rebates)

### Recommended Funding:
- **Rewards Pool**: 1,000,000 OCT initial
- **Protection Pool**: 500,000 OCT
- **Competition Pool**: 100,000 OCT/month
- **Social Pool**: 50,000 OCT/month
- **Referral Pool**: 250,000 OCT

**Total Launch Budget**: ~2M OCT

---

## 🚀 Launch Strategy

### Phase 1: Pre-Launch (Week 1-2)
- Fund all reward pools
- Set up referral system
- Create first competition
- Prepare marketing materials

### Phase 2: Soft Launch (Week 3-4)
- Open early adopter registration
- Activate first trade protection
- Start referral program
- Run first competition

### Phase 3: Full Launch (Month 2+)
- Scale competitions
- Expand social features
- Introduce tier benefits
- Launch leaderboards

---

## 📈 Marketing Angles

### Key Messages:

1. **"Risk-Free First Trade"**
   - 100% loss protection
   - Perfect for beginners

2. **"Earn While You Trade"**
   - Volume rewards
   - Referral income
   - Social earnings

3. **"VIP Treatment for Active Traders"**
   - Fee discounts up to 60%
   - Exclusive competitions
   - Legendary NFT badges

4. **"Share Your Success"**
   - Viral bonus at 100 likes
   - Copy-trade rewards
   - Community building

5. **"First 1,000 Get 100 OCT Free"**
   - Early adopter exclusivity
   - Limited time offer
   - Create FOMO

---

## 🛠 Technical Integration

### Admin Setup Functions:

```move
// Fund all pools
fund_rewards_pool(rewards_pool, payment, 1000000_OCT, ctx)
fund_referral_pool(referral_system, payment, 250000_OCT, ctx)
fund_protection_pool(protection_system, payment, 500000_OCT, ctx)
fund_prize_pool(competition_manager, payment, 100000_OCT, ctx)
fund_social_pool(social_system, payment, 50000_OCT, ctx)

// Create first competition
create_competition(
    manager,
    "Launch Week Volume Contest",
    COMPETITION_TYPE_VOLUME,
    DURATION_WEEKLY,
    10000_OCT,
    clock,
    ctx
)
```

### Main Contract Integration Points:

You'll need to update [perp.move](sources/perp.move) to call these modules:

1. **On position open**: Record volume, update tiers, track achievements
2. **On position close**: Activate protection if needed, distribute rewards
3. **On fee payment**: Apply discounts, record referral rewards
4. **On liquidation**: Update liquidation hunter stats

---

## 📞 Support & Documentation

### User Resources:
- **Referral Dashboard**: Track earnings and referrals
- **Achievement Gallery**: View unlocked NFTs
- **Competition Leaderboard**: Real-time rankings
- **Social Feed**: Browse shared trades
- **Protection Status**: Check eligibility

### Analytics Dashboard:
- Total users protected
- Referral conversion rate
- Competition participation
- Social engagement metrics
- Fee tier distribution

---

## 🎯 Success Metrics

### Track These KPIs:

1. **User Acquisition:**
   - Referral conversion rate
   - Early adopter claim rate
   - First trade protection usage

2. **Engagement:**
   - Competition participation
   - Social shares per user
   - Achievement unlock rate

3. **Retention:**
   - Tier progression rate
   - Repeat competition entries
   - Referral program activity

4. **Revenue Impact:**
   - Fee discount vs volume increase
   - Cost per acquisition
   - Lifetime value

---

## 🌟 Conclusion

You now have a **complete user acquisition ecosystem** featuring:

✅ **7 Promotional Modules**
✅ **Viral Referral System**
✅ **Gamified Achievements**
✅ **Risk-Free Onboarding**
✅ **Competitive Trading**
✅ **Social Engagement**
✅ **Loyalty Rewards**

These features work together to create a **sticky, engaging platform** that attracts new users and keeps them trading.

**Next Steps:**
1. Review and test each module
2. Fund reward pools
3. Create marketing materials
4. Launch with early adopter campaign
5. Monitor metrics and optimize

Good luck with your launch! 🚀
