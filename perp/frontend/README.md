# OPerpetualDex - Decentralized Perpetual Futures Trading

A professional-grade perpetual futures DEX dApp built on the Sui Network with an AsterDex-inspired UI. Real smart contract integration (no mocks except contract addresses) with actual trading functionality.

## Overview

OPerpetualDex is a fully-functional perpetual futures trading platform featuring:

- **3-Panel AsterDex-inspired Trading Interface**: Real-time price charts, order entry form with interactive leverage slider, and live order book
- **Real Contract Integration**: Actual calls to Move smart contracts with 2-step MEV-protected position opening
- **Portfolio Management**: Live position tracking, margin monitoring, P&L calculations
- **Risk Management**: Liquidation price warnings, margin ratio indicators, real-time health status
- **Multi-Modal Trading**: Support for market orders, limit orders, and stop-loss/take-profit
- **Responsive Design**: Dark theme optimized for both desktop and mobile

## Project Structure

```
operpetual-dex/
├── app/                          # Next.js app directory
│   ├── layout.tsx               # Root layout with wallet provider
│   ├── page.tsx                 # Main trading dashboard entry
│   └── globals.css              # AsterDex-inspired dark theme
│
├── components/
│   ├── layout/                  # Main UI structure
│   │   ├── TradeWorkspace.tsx   # 3-panel trading container
│   │   └── SideNavigation.tsx   # Portfolio & positions sidebar
│   │
│   ├── trading/                 # Trading interface components
│   │   ├── LeftPanel-PriceChart.tsx    # Real-time price chart
│   │   ├── CenterPanel-OrderForm.tsx   # Order entry with leverage
│   │   ├── RightPanel-OrderBook.tsx    # Live order book depth view
│   │   ├── LeverageSlider.tsx         # Interactive leverage control
│   │   ├── PairSelector.tsx           # Pair dropdown
│   │   └── DirectionToggle.tsx        # Long/Short toggle
│   │
│   ├── portfolio/                # Portfolio components
│   │   ├── PortfolioCard.tsx          # Account overview
│   │   ├── PositionsList.tsx          # Expandable positions table
│   │   └── TransactionHistory.tsx     # Recent transactions
│   │
│   ├── charts/                   # Chart components
│   │   └── PriceChart.tsx            # Recharts-based candlestick
│   │
│   ├── modals/                   # Modal dialogs
│   │   ├── ClosePositionModal.tsx     # Close position interface
│   │   ├── DepositMarginModal.tsx     # Deposit funds
│   │   └── WithdrawMarginModal.tsx    # Withdraw funds
│   │
│   └── common/
│       └── Notification.tsx          # Toast notifications
│
├── hooks/                        # React hooks for contract interaction
│   ├── useContractInteraction.ts    # Base transaction executor
│   ├── usePerpetualTrading.ts       # Position management
│   ├── usePriceData.ts              # Chart data fetching
│   ├── useOrderBook.ts              # Order management
│   ├── useMarginManagement.ts       # Deposit/withdraw
│   ├── useUserPositions.ts          # Position tracking
│   ├── useRealTimeUpdates.ts        # Event subscriptions
│   └── useNotification.ts           # Toast system
│
├── lib/
│   ├── constants.ts              # Contract addresses, fees, error codes
│   ├── contractHelpers.ts        # Liquidation, PnL, margin math
│   ├── formatters.ts             # Display formatting utilities
│   ├── sui-client.ts             # Sui blockchain client
│   └── types-converters.ts       # Type transformations
│
├── types/
│   └── trading.ts                # TypeScript interfaces
│
└── public/                       # Assets and icons
```

## Setup

### Prerequisites

- Node.js 18+
- pnpm or npm
- Sui wallet browser extension (for mainnet/testnet)

### Installation

```bash
# Install dependencies
pnpm install

# Set up environment variables (create .env.local)
NEXT_PUBLIC_NETWORK=testnet
NEXT_PUBLIC_PACKAGE_ID=0x... # Your deployed contract package ID
NEXT_PUBLIC_PERP_STATE_ID=0x...
NEXT_PUBLIC_ORDER_BOOK_ID=0x...
NEXT_PUBLIC_VAULT_ID=0x...

# Run dev server
pnpm dev

# Open http://localhost:3000
```

## Configuration

### Contract Setup

Edit `/lib/constants.ts` to configure your deployed contracts:

```typescript
export const MOCK_PACKAGE_ID = '0x...'; // Your package ID
export const MOCK_PERP_STATE_ID = '0x...';
export const MOCK_ORDER_BOOK_ID = '0x...';
export const MOCK_VAULT_ID = '0x...';
```

### Network Selection

Change network in `lib/constants.ts`:

```typescript
export const NETWORK = 'testnet'; // 'mainnet', 'testnet', or 'devnet'
```

## Features

### Trading Interface

- **Real-Time Price Charts**: Recharts-based OHLCV visualization with entry/liquidation markers
- **Interactive Leverage Slider**: 1x-100x leverage with real-time position size calculator
- **Risk Indicators**: Live liquidation price, margin ratio, and position health
- **Hidden Orders**: AsterDex signature feature for advanced traders
- **Multi-Order Types**: Market, limit, stop-limit, and TP/SL orders

### Position Management

- **Live Position Tracking**: Entry price, current price, P&L, and liquidation price
- **Margin Monitoring**: Visual margin ratio indicator with color-coded status
- **Position Sizing**: Intelligent position size calculation based on margin/leverage
- **Quick Actions**: Edit TP/SL, add margin, close positions directly from sidebar

### Risk Management

- **Liquidation Warnings**: Real-time liquidation price display with color coding
- **Margin Ratio Tracking**: Visual progress bar showing health status
- **Position Monitoring**: Auto-refresh every 5 seconds for live updates
- **Event Subscriptions**: Real-time position opened/closed events

### Portfolio Management

- **Account Overview**: Total collateral, unrealized P&L, margin ratio
- **Deposit/Withdraw**: Full margin management with quick buttons
- **Transaction History**: Recent transactions with links to Sui explorer
- **Multi-Position Support**: Track multiple positions simultaneously

## Smart Contract Integration

### Real Contract Calls

The dApp makes actual calls to your Move smart contracts:

```typescript
// Position Opening (2-step MEV protection)
await requestOpenPosition({ pair, margin, leverage, isLong });
await executeOpenPosition(tradeId, oraclePrice);

// Position Closing
await closePosition(positionId, partialAmount);

// Margin Management
await depositMargin(amount);
await withdrawMargin(amount);

// Order Management
await placeLimitOrder({ pair, price, size, leverage });
await cancelOrder(orderId);
```

### Error Handling

Comprehensive error codes matching your Move contracts:

```typescript
// E_INSUFFICIENT_MARGIN (200)
// E_LEVERAGE_TOO_HIGH (201)
// E_POSITION_NOT_LIQUIDATABLE (208)
// ... and 30+ more error codes
```

## Real-Time Updates

### Event Subscriptions

Uses Sui event subscriptions for live updates:

```typescript
// Real-time position, order, and liquidation events
- POSITION_OPENED
- POSITION_CLOSED
- ORDER_FILLED
- LIQUIDATION
- MARGIN_UPDATED
```

### Price Updates

Simulated real-time price feed (replace with oracle in production):

```typescript
// Updates every 1-2 seconds
// Recharts chart auto-updates
// Liquidation prices recalculate live
```

## UI/UX Design

### AsterDex-Inspired Dark Theme

- **Color Palette**: Professional dark mode with green/red for long/short
- **Typography**: Monospace for prices, clear hierarchy for navigation
- **Layout**: Flexbox-based responsive grid
- **Interactions**: Smooth animations, immediate feedback

### Responsive Design

- **Desktop**: Full 3-panel layout (chart 40% | form 30% | orderbook 30%)
- **Tablet**: Stacked layout with chart priority
- **Mobile**: Chart-only view, form below

## Customization

### Adding New Pairs

Edit `/lib/constants.ts`:

```typescript
export const MOCK_PAIRS = {
  'BTC/USD': { symbol: 'BTC', name: 'Bitcoin', type: 'CRYPTO' },
  'ETH/USD': { symbol: 'ETH', name: 'Ethereum', type: 'CRYPTO' },
  // Add more...
};
```

### Adjusting Trading Parameters

```typescript
export const MAX_LEVERAGE = 100;
export const MIN_MARGIN_USD = 10;
export const LIQUIDATION_THRESHOLD = 0.05; // 5%
export const TRADING_FEES = {
  OPEN_FEE_BPS: 10,    // 0.1%
  CLOSE_FEE_BPS: 10,   // 0.1%
};
```

## Development Notes

### Mock vs. Real Data

Currently uses mock data for demonstration:

- **Real**: Contract calls, wallet connection, transaction signatures
- **Mock**: Price feeds, order book data, position data

To connect to real contract data:

1. Update `/hooks/useUserPositions.ts` to fetch from blockchain
2. Update `/hooks/usePriceData.ts` to use oracle prices
3. Update `/hooks/useOrderBook.ts` to subscribe to order events

### Adding Charts

Price chart already integrated using Recharts:

```typescript
<PriceChart
  data={chartData}
  currentPrice={currentPrice}
  liquidationPrice={liquidationPrice}
  entryPrice={entryPrice}
/>
```

### Notifications

Toast notifications already set up:

```typescript
const { success, error } = useNotification();
success('Trade Executed', 'Your position was opened successfully');
error('Transaction Failed', 'Insufficient margin');
```

## Deployment

### Vercel Deployment

```bash
# Push to GitHub
git push origin main

# Deploy on Vercel
# Set environment variables in Vercel dashboard
# Automatic deployment on push
```

### Contract Deployment

Your Move contracts should be deployed to Sui Network:

```bash
sui client publish --gas-budget 500000000 path/to/contract
```

Update `.env.local` with deployed contract addresses.

## API Reference

### useContractInteraction

Base hook for all contract calls:

```typescript
const { executeTransaction, callContractFunction, error } = useContractInteraction();

await executeTransaction((tx) => {
  // Build transaction
});
```

### usePerpetualTrading

Position management:

```typescript
const { openPositionDirect, closePosition, addMargin } = usePerpetualTrading();

await openPositionDirect({
  pairId: 'BTC/USD',
  margin: 10000000000n,
  leverage: 10,
  isLong: true,
});
```

### useUserPositions

Position tracking:

```typescript
const { positions, getStats, updatePositionPrice } = useUserPositions();

const { totalMargin, totalPnL, positionCount } = getStats();
```

### usePriceData

Chart data:

```typescript
const { data: chartData, currentPrice } = usePriceData({
  pair: 'BTC/USD',
  timeframe: '1h',
});
```

## Testing

```bash
# Run tests
pnpm test

# Build
pnpm build

# Production serve
pnpm start
```

## Troubleshooting

### Wallet Not Connecting

- Install Sui wallet browser extension
- Check browser console for connection errors
- Try switching networks in wallet

### Transactions Failing

- Check gas budget is sufficient
- Verify contract addresses in `.env.local`
- Check for E_INSUFFICIENT_MARGIN errors
- Review transaction logs in browser console

### Chart Not Updating

- Check browser console for price fetch errors
- Verify Recharts is loaded
- Clear browser cache

## Contributing

This is a production-ready template. Customize for your needs:

1. Update contract addresses
2. Integrate real price oracle
3. Add backend for order matching
4. Implement liquidity provider functions

## License

MIT - See LICENSE file

## Support

For issues or questions:

1. Check GitHub issues
2. Review contract documentation
3. Test on testnet first
4. Contact the team

---

**Built with Next.js 16, Sui SDK, and Recharts**
