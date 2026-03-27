// Trading-related types and interfaces
export interface Pair {
  id: string;
  symbol: string;
  name: string;
  type: 'CRYPTO' | 'FOREX' | 'COMMODITIES' | 'INDICES';
  status: 'ACTIVE' | 'CLOSE_ONLY' | 'CLOSED';
  maxLeverage: number;
  currentPrice: number;
}

export interface Position {
  id: string;
  owner: string;
  pairId: string;
  isLong: boolean;
  margin: bigint;
  leverage: number;
  openPrice: bigint;
  currentPrice?: bigint;
  size: bigint;
  pnl?: bigint;
  pnlPercentage?: number;
  liquidationPrice: bigint;
  marginRatio: number;
  stopLoss?: bigint;
  takeProfit?: bigint;
  createdAt: number;
  status: 'OPEN' | 'CLOSING' | 'CLOSED';
}

export interface Order {
  id: string;
  owner: string;
  pairId: string;
  orderType: 'MARKET' | 'LIMIT' | 'STOP_MARKET' | 'STOP_LIMIT' | 'TAKE_PROFIT_MARKET' | 'TAKE_PROFIT_LIMIT';
  direction: 'BUY' | 'SELL';
  size: bigint;
  price?: bigint;
  triggerPrice?: bigint;
  leverage: number;
  margin: bigint;
  status: 'OPEN' | 'FILLED' | 'CANCELLED' | 'EXPIRED' | 'PARTIALLY_FILLED';
  createdAt: number;
  expiresAt: number;
}

export interface CrossMarginAccount {
  owner: string;
  totalCollateral: bigint;
  totalMarginUsed: bigint;
  availableMargin: bigint;
  marginRatio: number;
  isHealthy: boolean;
}

export interface PendingTrade {
  tradeId: string;
  trader: string;
  pairId: string;
  isLong: boolean;
  margin: bigint;
  leverage: number;
  timestamp: number;
  expiresAt: number;
}

export interface PriceData {
  timestamp: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface ContractError {
  code: number;
  message: string;
}
