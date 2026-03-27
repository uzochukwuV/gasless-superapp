/**
 * Price Feed Updater for One Blockchain
 * Updates USDT, OCT, BNB, and ETH prices
 *
 * Usage:
 *   node update_prices.js
 *
 * Environment variables:
 *   PRIVATE_KEY - Your wallet private key
 *   RPC_URL - One blockchain RPC endpoint
 *   PRICE_FEED_ID - Price feed object ID
 *   API_KEY - CoinGecko/CoinMarketCap API key (optional)
 */

const { JsonRpcProvider, Ed25519Keypair, RawSigner, TransactionBlock } = require('@mysten/sui.js');

// ============================================
// CONFIGURATION
// ============================================

const CONFIG = {
    rpcUrl: process.env.RPC_URL || 'https://rpc.onechain.network',
    privateKey: process.env.PRIVATE_KEY,
    priceFeedId: process.env.PRICE_FEED_ID,
    updateInterval: 60000, // Update every 60 seconds
    priceApiUrl: 'https://api.coingecko.com/api/v3/simple/price',
    tokens: {
        USDT: { coingeckoId: 'tether', decimals: 6 },
        OCT: { coingeckoId: 'octopus-network', decimals: 18 },
        BNB: { coingeckoId: 'binancecoin', decimals: 18 },
        ETH: { coingeckoId: 'ethereum', decimals: 18 },
    },
};

// ============================================
// PRICE FETCHING
// ============================================

/**
 * Fetch prices from CoinGecko API
 */
async function fetchPrices() {
    try {
        const ids = Object.values(CONFIG.tokens).map(t => t.coingeckoId).join(',');
        const url = `${CONFIG.priceApiUrl}?ids=${ids}&vs_currencies=usd&include_24hr_change=true`;

        const response = await fetch(url);
        const data = await response.json();

        const prices = {};
        for (const [symbol, config] of Object.entries(CONFIG.tokens)) {
            const priceData = data[config.coingeckoId];
            if (priceData) {
                // Convert to 6 decimal precision (1_000_000 = $1.00)
                prices[symbol] = {
                    price: Math.round(priceData.usd * 1_000_000),
                    change24h: priceData.usd_24h_change || 0,
                    confidence: 1000, // 0.1% confidence interval
                };
            }
        }

        return prices;
    } catch (error) {
        console.error('Error fetching prices:', error.message);
        return null;
    }
}

/**
 * Fallback: Use mock prices for testing
 */
function getMockPrices() {
    return {
        USDT: { price: 1_000_000, change24h: 0.01, confidence: 1000 },
        OCT: { price: 2_500_000, change24h: 5.2, confidence: 2000 },
        BNB: { price: 310_000_000, change24h: -1.5, confidence: 5000 },
        ETH: { price: 2200_000_000, change24h: 3.7, confidence: 10000 },
    };
}

// ============================================
// BLOCKCHAIN INTERACTION
// ============================================

/**
 * Initialize One blockchain connection
 */
function initializeProvider() {
    const provider = new JsonRpcProvider(CONFIG.rpcUrl);
    const keypair = Ed25519Keypair.fromSecretKey(Buffer.from(CONFIG.privateKey, 'hex'));
    const signer = new RawSigner(keypair, provider);

    return { provider, signer, keypair };
}

/**
 * Update prices on-chain using batch update
 */
async function updatePricesOnChain(signer, prices) {
    try {
        const tx = new TransactionBlock();

        // Prepare batch data
        const tokens = [];
        const priceValues = [];
        const confidences = [];

        for (const [symbol, data] of Object.entries(prices)) {
            tokens.push(symbol);
            priceValues.push(data.price);
            confidences.push(data.confidence);
        }

        // Call update_prices_batch
        tx.moveCall({
            target: `${process.env.PACKAGE_ID}::price_feed::update_prices_batch`,
            arguments: [
                tx.object(CONFIG.priceFeedId),
                tx.pure(tokens),
                tx.pure(priceValues, 'vector<u64>'),
                tx.pure(confidences, 'vector<u64>'),
                tx.object('0x6'), // Clock object
            ],
        });

        // Execute transaction
        const result = await signer.signAndExecuteTransactionBlock({
            transactionBlock: tx,
            options: {
                showEffects: true,
                showEvents: true,
            },
        });

        return result;
    } catch (error) {
        console.error('Error updating prices on-chain:', error.message);
        return null;
    }
}

/**
 * Update single price (alternative method)
 */
async function updateSinglePrice(signer, symbol, priceData) {
    try {
        const tx = new TransactionBlock();

        tx.moveCall({
            target: `${process.env.PACKAGE_ID}::price_feed::update_price`,
            arguments: [
                tx.object(CONFIG.priceFeedId),
                tx.pure(symbol),
                tx.pure(priceData.price, 'u64'),
                tx.pure(priceData.confidence, 'u64'),
                tx.object('0x6'), // Clock object
            ],
        });

        const result = await signer.signAndExecuteTransactionBlock({
            transactionBlock: tx,
            options: {
                showEffects: true,
            },
        });

        return result;
    } catch (error) {
        console.error(`Error updating ${symbol}:`, error.message);
        return null;
    }
}

// ============================================
// MONITORING & LOGGING
// ============================================

/**
 * Display current prices
 */
function displayPrices(prices) {
    console.log('\n' + '='.repeat(60));
    console.log('PRICE UPDATE - ' + new Date().toISOString());
    console.log('='.repeat(60));

    for (const [symbol, data] of Object.entries(prices)) {
        const usdPrice = (data.price / 1_000_000).toFixed(6);
        const change = data.change24h >= 0 ? `+${data.change24h.toFixed(2)}%` : `${data.change24h.toFixed(2)}%`;
        const changeColor = data.change24h >= 0 ? '\x1b[32m' : '\x1b[31m'; // Green/Red

        console.log(`${symbol.padEnd(6)} $${usdPrice.padStart(12)} ${changeColor}${change}\x1b[0m`);
    }

    console.log('='.repeat(60) + '\n');
}

/**
 * Log transaction result
 */
function logTransactionResult(result) {
    if (!result) {
        console.error('❌ Transaction failed');
        return;
    }

    const status = result.effects?.status?.status;
    if (status === 'success') {
        console.log(`✅ Prices updated successfully`);
        console.log(`   Digest: ${result.digest}`);

        // Log gas used
        if (result.effects?.gasUsed) {
            const gasUsed = result.effects.gasUsed.computationCost;
            console.log(`   Gas used: ${gasUsed}`);
        }
    } else {
        console.error(`❌ Transaction failed: ${status}`);
    }
}

// ============================================
// MAIN UPDATER LOOP
// ============================================

/**
 * Main price updater function
 */
async function updatePrices() {
    console.log('Fetching latest prices...');

    // Fetch prices (try API first, fallback to mock)
    let prices = await fetchPrices();
    if (!prices) {
        console.log('Using mock prices for testing...');
        prices = getMockPrices();
    }

    // Display prices
    displayPrices(prices);

    // Update on-chain (if configured)
    if (CONFIG.priceFeedId && CONFIG.privateKey) {
        const { signer } = initializeProvider();
        const result = await updatePricesOnChain(signer, prices);
        logTransactionResult(result);
    } else {
        console.log('⚠️  No price feed configured. Set PRICE_FEED_ID and PRIVATE_KEY to enable on-chain updates.');
    }
}

/**
 * Start continuous price updates
 */
async function startPriceUpdater() {
    console.log(`
╔═══════════════════════════════════════════════════════════╗
║           ONE BLOCKCHAIN PRICE FEED UPDATER               ║
╚═══════════════════════════════════════════════════════════╝

Configuration:
  - RPC: ${CONFIG.rpcUrl}
  - Update Interval: ${CONFIG.updateInterval / 1000}s
  - Tokens: ${Object.keys(CONFIG.tokens).join(', ')}
  - Price Feed: ${CONFIG.priceFeedId || 'Not configured'}

Starting price updater...
`);

    // Initial update
    await updatePrices();

    // Set up interval
    setInterval(async () => {
        await updatePrices();
    }, CONFIG.updateInterval);
}

// ============================================
// CLI COMMANDS
// ============================================

/**
 * Add a new price updater address
 */
async function addUpdater(updaterAddress) {
    const { signer } = initializeProvider();
    const tx = new TransactionBlock();

    tx.moveCall({
        target: `${process.env.PACKAGE_ID}::price_feed::add_updater`,
        arguments: [
            tx.object(CONFIG.priceFeedId),
            tx.pure(updaterAddress, 'address'),
        ],
    });

    const result = await signer.signAndExecuteTransactionBlock({
        transactionBlock: tx,
        options: { showEffects: true },
    });

    console.log(`Updater ${updaterAddress} added:`, result.digest);
}

/**
 * Query current prices from chain
 */
async function queryPrices() {
    const { provider } = initializeProvider();

    // This would need to call a view function
    // Implementation depends on One blockchain's query methods
    console.log('Querying on-chain prices...');
    // TODO: Implement price query
}

// ============================================
// ENTRY POINT
// ============================================

const command = process.argv[2];

switch (command) {
    case 'start':
        startPriceUpdater();
        break;
    case 'once':
        updatePrices().then(() => process.exit(0));
        break;
    case 'add-updater':
        addUpdater(process.argv[3]).then(() => process.exit(0));
        break;
    case 'query':
        queryPrices().then(() => process.exit(0));
        break;
    default:
        console.log(`
Usage:
  node update_prices.js [command]

Commands:
  start          Start continuous price updates (default)
  once           Update prices once and exit
  add-updater    Add a new authorized price updater
  query          Query current on-chain prices

Environment variables required:
  PRIVATE_KEY      - Your wallet private key
  PRICE_FEED_ID    - Price feed object ID
  PACKAGE_ID       - Deployed package ID
  RPC_URL          - One blockchain RPC (optional)
        `);
        process.exit(1);
}
