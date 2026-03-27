// Number and data formatting utilities

/**
 * Format number with thousand separators
 */
export function formatNumber(
  value: number | string,
  decimals: number = 2,
  showSign: boolean = false
): string {
  const num = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(num)) return '0';

  const sign = showSign && num > 0 ? '+' : '';
  return (
    sign +
    num.toLocaleString('en-US', {
      minimumFractionDigits: decimals,
      maximumFractionDigits: decimals,
    })
  );
}

/**
 * Format price (USD)
 */
export function formatPrice(value: number | string, decimals: number = 2): string {
  return '$' + formatNumber(value, decimals);
}

/**
 * Format large numbers with K, M, B suffix
 */
export function formatCompact(value: number | string): string {
  const num = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(num)) return '0';

  if (Math.abs(num) >= 1e9) {
    return (num / 1e9).toFixed(2) + 'B';
  }
  if (Math.abs(num) >= 1e6) {
    return (num / 1e6).toFixed(2) + 'M';
  }
  if (Math.abs(num) >= 1e3) {
    return (num / 1e3).toFixed(2) + 'K';
  }
  return num.toFixed(2);
}

/**
 * Format percentage
 */
export function formatPercent(
  value: number | string,
  decimals: number = 2,
  showSign: boolean = true
): string {
  const num = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(num)) return '0%';

  const sign = showSign && num > 0 ? '+' : '';
  return sign + num.toFixed(decimals) + '%';
}

/**
 * Format P&L with color indicator string
 */
export function formatPnL(value: number | string, decimals: number = 2): string {
  const num = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(num)) return '0';

  const sign = num > 0 ? '+' : '';
  return sign + num.toFixed(decimals);
}

/**
 * Format margin ratio
 */
export function formatMarginRatio(value: number): string {
  if (!isFinite(value)) return '∞';
  return formatPercent(value * 100, 1);
}

/**
 * Format leverage with x suffix
 */
export function formatLeverage(value: number | string): string {
  const num = typeof value === 'string' ? parseFloat(value) : value;
  if (isNaN(num)) return '0x';
  return num.toFixed(1) + 'x';
}

/**
 * Format timestamp to readable date
 */
export function formatDate(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

/**
 * Format timestamp to time HH:MM:SS
 */
export function formatTime(timestamp: number): string {
  const date = new Date(timestamp * 1000);
  return date.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
}

/**
 * Format timestamp to full datetime
 */
export function formatDateTime(timestamp: number): string {
  return formatDate(timestamp) + ' ' + formatTime(timestamp);
}

/**
 * Format address (shorten)
 */
export function formatAddress(address: string, chars: number = 4): string {
  if (!address || address.length < 10) return address;
  return address.slice(0, chars + 2) + '...' + address.slice(-chars);
}

/**
 * Format transaction hash (shorten)
 */
export function formatTxHash(hash: string, chars: number = 6): string {
  if (!hash || hash.length < 20) return hash;
  return hash.slice(0, chars + 2) + '...' + hash.slice(-chars);
}

/**
 * Get color class for P&L value
 */
export function getPnLColorClass(value: number): string {
  if (value > 0) return 'text-green-500';
  if (value < 0) return 'text-red-500';
  return 'text-foreground';
}

/**
 * Get color class for margin ratio
 */
export function getMarginColorClass(ratio: number): string {
  if (ratio > 0.5) return 'text-green-500';
  if (ratio > 0.2) return 'text-yellow-500';
  return 'text-red-500';
}

/**
 * Get status badge class
 */
export function getStatusColorClass(status: string): string {
  const statusLower = status.toLowerCase();
  if (statusLower.includes('open')) return 'bg-blue-500/10 text-blue-500';
  if (statusLower.includes('closed')) return 'bg-gray-500/10 text-gray-500';
  if (statusLower.includes('filled')) return 'bg-green-500/10 text-green-500';
  if (statusLower.includes('cancel')) return 'bg-red-500/10 text-red-500';
  if (statusLower.includes('expired')) return 'bg-yellow-500/10 text-yellow-500';
  return 'bg-gray-500/10 text-gray-500';
}

/**
 * Get direction badge text
 */
export function getDirectionText(isLong: boolean | string): string {
  const long = typeof isLong === 'string' ? isLong.toLowerCase() === 'long' : isLong;
  return long ? 'LONG' : 'SHORT';
}

/**
 * Get direction color class
 */
export function getDirectionColorClass(isLong: boolean | string): string {
  const long = typeof isLong === 'string' ? isLong.toLowerCase() === 'long' : isLong;
  return long ? 'text-green-500' : 'text-red-500';
}

/**
 * Get direction badge class
 */
export function getDirectionBadgeClass(isLong: boolean | string): string {
  const long = typeof isLong === 'string' ? isLong.toLowerCase() === 'long' : isLong;
  return long ? 'bg-green-500/10 text-green-500' : 'bg-red-500/10 text-red-500';
}
