// Contract interaction helpers and calculations
import {
  PRICE_PRECISION,
  INITIAL_MARGIN_REQUIREMENT,
  LIQUIDATION_THRESHOLD,
  TRADING_FEES,
  BPS,
} from './constants';

// ============================================
// CALCULATION HELPERS
// ============================================

/**
 * Calculate liquidation price for a position
 */
export function calculateLiquidationPrice(
  entryPrice: bigint,
  isLong: boolean,
  margin: bigint,
  leverage: number,
  pairDecimals: number = 2
): bigint {
  const leverageDecimal = BigInt(leverage);
  const denominator = leverageDecimal * LIQUIDATION_THRESHOLD * BigInt(10 ** pairDecimals);

  if (isLong) {
    // For long: liquidation price = entry price * (1 - margin/leverage/position)
    return entryPrice - (entryPrice * margin) / denominator;
  } else {
    // For short: liquidation price = entry price * (1 + margin/leverage/position)
    return entryPrice + (entryPrice * margin) / denominator;
  }
}

/**
 * Calculate required margin for a position
 */
export function calculateRequiredMargin(
  size: bigint,
  entryPrice: bigint,
  leverage: number
): bigint {
  // Required margin = (size * price) / leverage
  const leverageDecimal = BigInt(leverage);
  return (size * entryPrice) / leverageDecimal;
}

/**
 * Calculate position size from margin and leverage
 */
export function calculatePositionSize(
  margin: bigint,
  entryPrice: bigint,
  leverage: number
): bigint {
  // Position size = (margin * leverage) / price
  const leverageDecimal = BigInt(leverage);
  return (margin * leverageDecimal) / entryPrice;
}

/**
 * Calculate unrealized P&L
 */
export function calculatePnL(
  isLong: boolean,
  entryPrice: bigint,
  currentPrice: bigint,
  size: bigint
): bigint {
  if (isLong) {
    // Long P&L = (current - entry) * size
    return (currentPrice - entryPrice) * size;
  } else {
    // Short P&L = (entry - current) * size
    return (entryPrice - currentPrice) * size;
  }
}

/**
 * Calculate P&L percentage
 */
export function calculatePnLPercentage(
  pnl: bigint,
  margin: bigint
): number {
  if (margin === 0n) return 0;
  return Number((pnl * 10000n) / margin) / 100; // Return as percentage
}

/**
 * Calculate margin ratio (available margin / used margin)
 */
export function calculateMarginRatio(
  collateral: bigint,
  marginUsed: bigint
): number {
  if (marginUsed === 0n) return Infinity;
  return Number((collateral * 100n) / marginUsed) / 100;
}

/**
 * Calculate opening fee
 */
export function calculateOpeningFee(
  positionSize: bigint,
  entryPrice: bigint
): bigint {
  // Fee = (size * price * fee_bps) / 10000
  const feeAmount = (positionSize * entryPrice * BigInt(TRADING_FEES.OPEN_FEE_BPS)) / BPS;
  return feeAmount;
}

/**
 * Calculate closing fee
 */
export function calculateClosingFee(
  positionSize: bigint,
  exitPrice: bigint,
  pnl: bigint
): bigint {
  // Close fee = max((size * price * fee_bps), pnl * min_close_fee)
  const baseFee = (positionSize * exitPrice * BigInt(TRADING_FEES.CLOSE_FEE_BPS)) / BPS;
  const pnlBasedFee = (pnl * BigInt(TRADING_FEES.MIN_CLOSE_FEE_BPS)) / BPS;
  return baseFee > pnlBasedFee ? baseFee : pnlBasedFee;
}

/**
 * Check if position is liquidatable (margin ratio <= 5%)
 */
export function isPositionLiquidatable(marginRatio: number): boolean {
  return marginRatio <= LIQUIDATION_THRESHOLD * 100;
}

/**
 * Check if position is at risk (margin ratio <= 10%)
 */
export function isPositionAtRisk(marginRatio: number): boolean {
  return marginRatio <= INITIAL_MARGIN_REQUIREMENT * 100;
}

/**
 * Format price from contract (1e10 precision) to decimal
 */
export function formatPrice(price: bigint, decimals: number = 2): number {
  return Number(price) / Number(PRICE_PRECISION) * 10 ** (decimals - 2);
}

/**
 * Convert display price to contract format (1e10 precision)
 */
export function priceToContractFormat(price: number): bigint {
  return BigInt(Math.floor(price * Number(PRICE_PRECISION)));
}

/**
 * Format amount from Wei-like format to decimal
 */
export function formatAmount(amount: bigint, decimals: number = 6): number {
  return Number(amount) / 10 ** decimals;
}

/**
 * Convert display amount to contract format
 */
export function amountToContractFormat(amount: number, decimals: number = 6): bigint {
  return BigInt(Math.floor(amount * 10 ** decimals));
}

/**
 * Validate leverage is within bounds
 */
export function isValidLeverage(leverage: number, maxLeverage: number): boolean {
  return leverage >= 1 && leverage <= maxLeverage;
}

/**
 * Estimate gas cost for transaction (in SUI)
 */
export function estimateGasCost(txType: 'OPEN_POSITION' | 'CLOSE_POSITION' | 'LIMIT_ORDER'): number {
  const costs: Record<string, number> = {
    OPEN_POSITION: 0.01, // ~10 million MIST in SUI
    CLOSE_POSITION: 0.008,
    LIMIT_ORDER: 0.005,
  };
  return costs[txType] || 0.01;
}
