# 📊 One Blockchain Price Feed Oracle

A decentralized, multi-token price oracle for One blockchain that others can integrate into their protocols.

## 🎯 Features

- ✅ **Multi-token support** - USDT, OCT, BNB, ETH (easily extensible)
- ✅ **Batch updates** - Gas-efficient bulk price updates
- ✅ **Multi-updater support** - Decentralized price updates from multiple sources
- ✅ **Staleness protection** - Automatic price freshness checks
- ✅ **High precision** - 6 decimal USD prices (1_000_000 = $1.00)
- ✅ **Consumer-friendly API** - Simple integration for other protocols
- ✅ **Node.js updater** - Automated price updates from CoinGecko

## 📦 Smart Contract Architecture

### Core Functions

**For Price Updaters:**
```move
// Single price update
update_price(feed, token: "ETH", price: 2200_000_000, confidence: 10000, clock)

// Batch update (recommended)
update_prices_batch(
    feed,
    tokens: ["USDT", "OCT", "BNB", "ETH"],
    prices: [1_000_000, 2_500_000, 310_000_000, 2200_000_000],
    confidences: [1000, 2000, 5000, 10000],
    clock
)
```

**For Consumers (Other Protocols):**
```move
// Get current price with staleness check
let eth_price = price_feed::get_price(feed, string::utf8(b"ETH"), clock);

// Get price data with metadata
let (price, last_update, confidence, update_count) =
    price_feed::get_price_data(feed, string::utf8(b"ETH"));

// Check if price is fresh
if (price_feed::is_price_fresh(feed, string::utf8(b"ETH"), clock)) {
    // Use price
};

// Get conversion rate between two tokens (e.g., ETH/BNB)
let eth_bnb_rate = price_feed::get_conversion_rate(
    feed,
    string::utf8(b"ETH"),
    string::utf8(b"BNB"),
    clock
);

// Calculate USD value of token amount
let usd_value = price_feed::calculate_usd_value(
    feed,
    string::utf8(b"ETH"),
    amount: 1_000_000_000_000_000_000, // 1 ETH in wei
    decimals: 18,
    clock
);
```

**For Admins:**
```move
// Add authorized price updater
add_updater(feed, updater_address, ctx);

// Remove updater
remove_updater(feed, updater_address, ctx);

// Update max staleness
update_max_age(feed, new_max_age_ms: 300_000, ctx);
```

## 🚀 Deployment Guide

### 1. Deploy the Contract

```bash
cd gasless-superapp/perp
sui move build
sui client publish --gas-budget 100000000
```

Save the published **Package ID** and **Price Feed Object ID**.

### 2. Set Up Node.js Price Updater

```bash
cd scripts
npm install

# Copy and configure environment
cp .env.example .env
nano .env
```

Update `.env`:
```bash
RPC_URL=https://rpc.onechain.network
PRIVATE_KEY=your_private_key_hex
PACKAGE_ID=0xabcd1234...
PRICE_FEED_ID=0x5678efgh...
```

### 3. Start Price Updates

```bash
# One-time update
npm run update-once

# Continuous updates (every 60 seconds)
npm start
```

### 4. Add Additional Updaters (Optional)

```bash
node update_prices.js add-updater 0x<updater_address>
```

## 🔧 Integration Example

### Example: Using Price Feed in Your Protocol

```move
module my_protocol::defi_app {
    use perp::price_feed::{Self, PriceFeed};
    use one::clock::Clock;
    use std::string;

    public entry fun swap_with_oracle(
        price_feed: &PriceFeed,
        amount_in: u64,
        clock: &Clock
    ) {
        // Get current ETH price
        let eth_price = price_feed::get_price(
            price_feed,
            string::utf8(b"ETH"),
            clock
        );

        // Calculate swap output based on oracle price
        let amount_out = (amount_in * eth_price) / 1_000_000;

        // ... rest of swap logic
    }

    public fun check_collateral_value(
        price_feed: &PriceFeed,
        eth_amount: u64,
        clock: &Clock
    ): u64 {
        // Calculate USD value of ETH collateral
        price_feed::calculate_usd_value(
            price_feed,
            string::utf8(b"ETH"),
            eth_amount,
            18, // ETH decimals
            clock
        )
    }

    public fun get_eth_bnb_rate(
        price_feed: &PriceFeed,
        clock: &Clock
    ): u64 {
        // Get how much ETH equals 1 BNB
        price_feed::get_conversion_rate(
            price_feed,
            string::utf8(b"ETH"),
            string::utf8(b"BNB"),
            clock
        )
    }
}
```

## 📊 Supported Tokens

| Token | Symbol | CoinGecko ID | Decimals |
|-------|--------|--------------|----------|
| Tether | USDT | tether | 6 |
| Octopus | OCT | octopus-network | 18 |
| BNB | BNB | binancecoin | 18 |
| Ethereum | ETH | ethereum | 18 |

### Adding New Tokens

**In Smart Contract:**
The contract automatically supports any token symbol you provide - no code changes needed!

**In Node.js Updater:**
Edit `update_prices.js`:
```javascript
const CONFIG = {
    tokens: {
        USDT: { coingeckoId: 'tether', decimals: 6 },
        BTC: { coingeckoId: 'bitcoin', decimals: 8 }, // Add this
        // ... more tokens
    },
};
```

## 🔒 Security Features

1. **Multi-updater Authorization** - Admin controls who can update prices
2. **Staleness Protection** - Automatic rejection of outdated prices (default: 5 minutes)
3. **Price Validation** - Rejects zero or negative prices
4. **Confidence Intervals** - Track price reliability
5. **Event Logging** - All updates emit events for transparency

## 📈 Price Precision

Prices use 6 decimal precision for USD values:
- `1_000_000` = $1.00
- `2_500_000` = $2.50
- `310_000_000` = $310.00
- `2200_000_000` = $2200.00

## 🛠️ Advanced Usage

### Custom Price Sources

Replace CoinGecko with your own API:

```javascript
async function fetchPrices() {
    const response = await fetch('https://your-api.com/prices');
    const data = await response.json();

    return {
        ETH: {
            price: Math.round(data.ethereum.usd * 1_000_000),
            confidence: 1000,
        },
        // ... other tokens
    };
}
```

### Price Aggregation from Multiple Sources

```javascript
async function fetchAggregatedPrices() {
    const [coinGecko, binance, coinbase] = await Promise.all([
        fetchFromCoinGecko(),
        fetchFromBinance(),
        fetchFromCoinbase(),
    ]);

    // Take median price for reliability
    return {
        ETH: {
            price: median([coinGecko.ETH, binance.ETH, coinbase.ETH]),
            confidence: calculateConfidence([...]),
        },
    };
}
```

### Monitoring & Alerts

```javascript
// Add monitoring to update_prices.js
async function updatePrices() {
    const prices = await fetchPrices();

    // Alert on large price swings
    for (const [symbol, data] of Object.entries(prices)) {
        if (Math.abs(data.change24h) > 10) {
            sendAlert(`⚠️ ${symbol} price changed ${data.change24h}% in 24h`);
        }
    }

    // ... rest of update logic
}
```

## 🧪 Testing

Query prices from the blockchain:

```bash
# Using sui CLI
sui client call \
    --package $PACKAGE_ID \
    --module price_feed \
    --function get_price_data \
    --args $PRICE_FEED_ID '"ETH"' \
    --gas-budget 10000000
```

## 📝 Gas Optimization

The batch update function is **significantly more gas-efficient**:

- Single updates: ~0.001 SUI per token
- Batch update (4 tokens): ~0.002 SUI total
- **Savings: 50%** when updating multiple tokens

**Recommendation:** Always use `update_prices_batch()` for multiple tokens.

## 🔄 Update Strategies

### High-Frequency Trading
```javascript
const CONFIG = {
    updateInterval: 10000, // 10 seconds
};
```

### Standard DeFi
```javascript
const CONFIG = {
    updateInterval: 60000, // 60 seconds (default)
};
```

### Conservative (Gas-Saving)
```javascript
const CONFIG = {
    updateInterval: 300000, // 5 minutes
};
```

## 🌐 Public Access

**Other protocols can freely use your price feed** by referencing the shared `PriceFeed` object in their transactions. No special permissions needed for consumers!

Example transaction from another protocol:
```typescript
const tx = new TransactionBlock();

tx.moveCall({
    target: `${theirPackageId}::their_module::their_function`,
    arguments: [
        tx.object(YOUR_PRICE_FEED_ID), // They reference your feed
        // ... their other args
    ],
});
```

## 📞 Support & Contributing

- **Issues:** Report bugs or request features
- **Price Source Integrations:** PRs welcome for additional data sources
- **New Tokens:** Submit token addition requests with CoinGecko IDs

---

## 🎓 Example Integration: Perps Protocol

See [perp.move](sources/perp.move) for a complete example of integrating this price feed into a perpetuals protocol.

**Before (centralized oracle):**
```move
public struct PriceOracle has key {
    oct_price: u64,
    last_update: u64,
}
```

**After (using price_feed):**
```move
use perp::price_feed::{Self, PriceFeed};

public entry fun open_position(
    pool: &mut LiquidityPool,
    price_feed: &PriceFeed, // Use shared price feed
    collateral: Coin<OCT>,
    clock: &Clock,
) {
    let oct_price = price_feed::get_price(
        price_feed,
        price_feed::oct_symbol(),
        clock
    );

    // ... rest of logic
}
```

This creates a **decentralized, composable oracle** that any protocol on One blockchain can use! 🚀
