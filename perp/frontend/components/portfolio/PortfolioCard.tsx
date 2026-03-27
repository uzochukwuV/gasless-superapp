'use client';

import { formatNumber, getPnLColorClass } from '@/lib/formatters';

interface PortfolioCardProps {
  totalCollateral: number;
  totalPnL: number;
  marginRatio: number;
  isHealthy: boolean;
  isAtRisk: boolean;
  isLoading?: boolean;
}

export default function PortfolioCard({
  totalCollateral,
  totalPnL,
  marginRatio,
  isHealthy,
  isAtRisk,
  isLoading = false,
}: PortfolioCardProps) {
  const pnlPercentage = (totalPnL / totalCollateral) * 100;
  
  const getStatusBadge = () => {
    if (isAtRisk) return <span className="text-xs bg-red-500/20 text-red-500 px-2 py-1 rounded">AT RISK</span>;
    if (!isHealthy) return <span className="text-xs bg-yellow-500/20 text-yellow-500 px-2 py-1 rounded">WARNING</span>;
    return <span className="text-xs bg-green-500/20 text-green-500 px-2 py-1 rounded">HEALTHY</span>;
  };

  return (
    <div className={`border border-border rounded-lg p-4 bg-gradient-to-br from-blue-500/5 to-purple-500/5 ${isLoading ? 'animate-pulse' : ''}`}>
      <div className="space-y-4">
        {/* Header with Status */}
        <div className="flex justify-between items-start">
          <div className="text-xs text-muted-foreground font-semibold">PORTFOLIO</div>
          {getStatusBadge()}
        </div>

        {/* Total Collateral */}
        <div className="space-y-1">
          <div className="text-xs text-muted-foreground">Total Collateral</div>
          <div className="text-2xl font-bold text-foreground">
            ${formatNumber(totalCollateral, 2)}
          </div>
        </div>

        {/* P&L Display */}
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1">
            <div className="text-xs text-muted-foreground">P&L</div>
            <div className={`text-lg font-semibold ${getPnLColorClass(totalPnL)}`}>
              {totalPnL >= 0 ? '+' : ''}{formatNumber(totalPnL, 2)}
            </div>
          </div>
          <div className="space-y-1">
            <div className="text-xs text-muted-foreground">P&L %</div>
            <div className={`text-lg font-semibold ${getPnLColorClass(pnlPercentage)}`}>
              {pnlPercentage >= 0 ? '+' : ''}{pnlPercentage.toFixed(2)}%
            </div>
          </div>
        </div>

        {/* Margin Ratio with Visual Bar */}
        <div className="space-y-2">
          <div className="flex justify-between items-center">
            <div className="text-xs text-muted-foreground">Margin Ratio</div>
            <div className={`text-sm font-semibold ${marginRatio > 50 ? 'text-green-500' : marginRatio > 10 ? 'text-yellow-500' : 'text-red-500'}`}>
              {marginRatio.toFixed(1)}%
            </div>
          </div>
          <div className="w-full bg-black/30 rounded-full h-2 overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${
                marginRatio > 50 ? 'bg-green-500' : marginRatio > 10 ? 'bg-yellow-500' : 'bg-red-500'
              }`}
              style={{ width: `${Math.min(marginRatio, 100)}%` }}
            ></div>
          </div>
          <div className="text-xs text-muted-foreground">
            {marginRatio > 50 ? 'Safe' : marginRatio > 10 ? 'Warning' : 'Critical'}
          </div>
        </div>
      </div>
    </div>
  );
}
