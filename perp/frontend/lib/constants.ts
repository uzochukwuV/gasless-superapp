// Contract and network constants
export const NETWORK = 'testnet'; // 'mainnet' | 'testnet' | 'devnet'

// ============================================
// MOCK CONTRACT ADDRESSES
// ============================================
// REPLACE WITH YOUR DEPLOYED CONTRACT ADDRESSES
export const MOCK_PACKAGE_ID = '0x0000000000000000000000000000000000000000000000000000000000000001';
export const MOCK_PERP_STATE_ID = '0x0000000000000000000000000000000000000000000000000000000000000002';
export const MOCK_ORDER_BOOK_ID = '0x0000000000000000000000000000000000000000000000000000000000000003';
export const MOCK_VAULT_ID = '0x0000000000000000000000000000000000000000000000000000000000000004';

export const CONTRACTS = {
  PACKAGE_ID: MOCK_PACKAGE_ID,
  PERP_STATE_ID: MOCK_PERP_STATE_ID,
  ORDER_BOOK_ID: MOCK_ORDER_BOOK_ID,
  VAULT_ID: MOCK_VAULT_ID,
};

// ============================================
// COIN TYPES
// ============================================
export const USDC_TYPE = '0x2::coin::Coin<0x5d4b302506645c34f7f4589fd605ea0affb3caea920e24c64990ee69f68f82b1::usdc::USDC>';
export const SUI_TYPE = '0x2::sui::SUI';

// ============================================
// PRECISION CONSTANTS (Match Contract)
// ============================================
export const BPS = 10000n; // Basis points
export const PRECISION_5 = 100000n; // 1e5
export const PRICE_PRECISION = 10000000000n; // 1e10
export const FUNDING_PRECISION = 1000000000000000000n; // 1e18
export const HOLDING_FEE_PRECISION = 1000000000000n; // 1e12

// ============================================
// MARGIN MODE CONSTANTS
// ============================================
export const MARGIN_ISOLATED = 0;
export const MARGIN_CROSS = 1;

export const MARGIN_MODE = {
  ISOLATED: 'ISOLATED',
  CROSS: 'CROSS',
} as const;

// ============================================
// ORDER TYPES
// ============================================
export const ORDER_TYPE = {
  MARKET: 0,
  LIMIT: 1,
  STOP_MARKET: 2,
  STOP_LIMIT: 3,
  TAKE_PROFIT_MARKET: 4,
  TAKE_PROFIT_LIMIT: 5,
} as const;

// ============================================
// ORDER STATUS
// ============================================
export const ORDER_STATUS = {
  OPEN: 0,
  FILLED: 1,
  CANCELLED: 2,
  EXPIRED: 3,
  PARTIALLY_FILLED: 4,
} as const;

// ============================================
// PAIR STATUS
// ============================================
export const PAIR_STATUS = {
  ACTIVE: 0,
  CLOSE_ONLY: 1,
  CLOSED: 2,
} as const;

// ============================================
// TRADING CONSTRAINTS
// ============================================
export const MIN_LEVERAGE = 1;
export const MAX_LEVERAGE = 100;
export const MIN_MARGIN_USD = 10; // Minimum margin in USD
export const LIQUIDATION_THRESHOLD = 0.05; // 5% margin ratio
export const INITIAL_MARGIN_REQUIREMENT = 0.1; // 10% for opening

// ============================================
// FEE RATES (in basis points)
// ============================================
export const TRADING_FEES = {
  OPEN_FEE_BPS: 10, // 0.1%
  CLOSE_FEE_BPS: 10, // 0.1%
  MIN_CLOSE_FEE_BPS: 5, // 0.05%
} as const;

// ============================================
// TRANSACTION SETTINGS
// ============================================
export const TX_TIMEOUT_MS = 30000; // 30 seconds
export const POLLING_INTERVAL_MS = 2000; // 2 seconds for polling
export const MAX_RETRIES = 3;

// ============================================
// UI SETTINGS
// ============================================
export const PRICE_DECIMALS = 2;
export const AMOUNT_DECIMALS = 4;
export const PNL_DECIMALS = 2;

// ============================================
// CHART SETTINGS
// ============================================
export const CHART_TIMEFRAMES = [
  { label: '1m', value: '1m' },
  { label: '5m', value: '5m' },
  { label: '15m', value: '15m' },
  { label: '1h', value: '1h' },
  { label: '4h', value: '4h' },
  { label: '1d', value: '1d' },
] as const;

// ============================================
// MOCK TRADING PAIRS
// ============================================
export const MOCK_PAIRS: Record<string, { symbol: string; name: string; type: string }> = {
  'BTC/USD': { symbol: 'BTC', name: 'Bitcoin', type: 'CRYPTO' },
  'ETH/USD': { symbol: 'ETH', name: 'Ethereum', type: 'CRYPTO' },
  'SOL/USD': { symbol: 'SOL', name: 'Solana', type: 'CRYPTO' },
  'USDT/USD': { symbol: 'USDT', name: 'Tether', type: 'CRYPTO' },
} as const;

// ============================================
// ERROR CODES (Match Contract)
// ============================================
export const ERROR_CODES = {
  E_NOT_ADMIN: 100,
  E_PAIR_EXISTS: 101,
  E_PAIR_NOT_FOUND: 102,
  E_INSUFFICIENT_MARGIN: 200,
  E_LEVERAGE_TOO_HIGH: 201,
  E_POSITION_TOO_SMALL: 202,
  E_POSITION_TOO_LARGE: 203,
  E_OI_LIMIT_EXCEEDED: 204,
  E_NOT_POSITION_OWNER: 207,
  E_POSITION_NOT_LIQUIDATABLE: 208,
  E_PENDING_TRADE_NOT_FOUND: 209,
  E_TRADE_EXPIRED: 210,
  E_INSUFFICIENT_LIQUIDITY: 300,
  E_PRICE_STALE: 400,
  E_INVALID_PRICE: 401,
  E_ORDER_NOT_FOUND: 600,
  E_ORDER_EXPIRED: 602,
} as const;

export const ERROR_MESSAGES: Record<number, string> = {
  100: 'Not authorized',
  101: 'Pair already exists',
  102: 'Pair not found',
  200: 'Insufficient margin',
  201: 'Leverage too high',
  202: 'Position size too small',
  203: 'Position size too large',
  204: 'Open interest limit exceeded',
  207: 'Not position owner',
  208: 'Position not liquidatable',
  209: 'Pending trade not found',
  210: 'Trade expired',
  300: 'Insufficient liquidity',
  400: 'Price data is stale',
  401: 'Invalid price',
  600: 'Order not found',
  602: 'Order expired',
};
