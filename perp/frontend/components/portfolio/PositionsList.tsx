'use client';

import { useState } from 'react';
import { formatNumber, getDirectionColorClass, getPnLColorClass } from '@/lib/formatters';

interface Position {
  id: string;
  pair: string;
  isLong: boolean;
  size: number;
  entryPrice: number;
  currentPrice: number;
  pnl: number;
  liquidationPrice: number;
  marginRatio: number;
}

// Mock positions for demo
const MOCK_POSITIONS: Position[] = [
  {
    id: '1',
    pair: 'BTC/USD',
    isLong: true,
    size: 0.5,
    entryPrice: 44000,
    currentPrice: 45230,
    pnl: 615,
    liquidationPrice: 35000,
    marginRatio: 75,
  },
  {
    id: '2',
    pair: 'ETH/USD',
    isLong: false,
    size: 5,
    entryPrice: 2350,
    currentPrice: 2340,
    pnl: 50,
    liquidationPrice: 2500,
    marginRatio: 85,
  },
];

interface PositionsListProps {
  isLoading?: boolean;
}

export default function PositionsList({ isLoading = false }: PositionsListProps) {
  const [expandedId, setExpandedId] = useState<string | null>(null);

  if (isLoading) {
    return (
      <div className="space-y-2">
        {[1, 2].map((i) => (
          <div key={i} className="h-16 bg-black/20 rounded animate-pulse"></div>
        ))}
      </div>
    );
  }

  if (MOCK_POSITIONS.length === 0) {
    return (
      <div className="text-center py-6">
        <div className="text-xs text-muted-foreground">No open positions</div>
        <div className="text-xs text-muted-foreground mt-2">Open a trade to get started</div>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {MOCK_POSITIONS.map((position) => (
        <div key={position.id} className="space-y-1">
          {/* Position Header */}
          <button
            onClick={() => setExpandedId(expandedId === position.id ? null : position.id)}
            className="w-full p-3 border border-border rounded hover:bg-black/20 transition-colors text-left"
          >
            <div className="flex justify-between items-start mb-2">
              <div className="space-y-1">
                <div className="font-medium text-sm">{position.pair}</div>
                <div className={`text-xs font-semibold ${getDirectionColorClass(position.isLong)}`}>
                  {position.isLong ? 'LONG' : 'SHORT'}
                </div>
              </div>
              <div className="text-right space-y-1">
                <div className={`text-sm font-semibold ${getPnLColorClass(position.pnl)}`}>
                  {position.pnl >= 0 ? '+' : ''}{formatNumber(position.pnl, 2)}
                </div>
                <div className="text-xs text-muted-foreground">
                  {(position.currentPrice - position.entryPrice).toFixed(0)}
                </div>
              </div>
            </div>
            <div className="text-xs text-muted-foreground flex justify-between">
              <span>{position.size} BTC/ETH</span>
              <span>{formatNumber(position.marginRatio, 0)}% margin</span>
            </div>
          </button>

          {/* Expanded Details */}
          {expandedId === position.id && (
            <div className="p-3 border border-border rounded bg-black/30 space-y-2 animate-slide-in-left">
              <div className="grid grid-cols-2 gap-2 text-xs">
                <div>
                  <div className="text-muted-foreground">Entry Price</div>
                  <div className="font-mono">${formatNumber(position.entryPrice, 2)}</div>
                </div>
                <div>
                  <div className="text-muted-foreground">Current Price</div>
                  <div className="font-mono">${formatNumber(position.currentPrice, 2)}</div>
                </div>
                <div>
                  <div className="text-muted-foreground">Liquidation</div>
                  <div className="font-mono text-red-500">${formatNumber(position.liquidationPrice, 2)}</div>
                </div>
                <div>
                  <div className="text-muted-foreground">Margin Ratio</div>
                  <div className="font-mono">{formatNumber(position.marginRatio, 1)}%</div>
                </div>
              </div>
              <div className="space-y-2 pt-2 border-t border-border">
                <button className="w-full px-3 py-2 text-xs bg-blue-500/10 text-blue-500 border border-blue-500/30 rounded hover:bg-blue-500/20 transition-colors">
                  Edit TP/SL
                </button>
                <button className="w-full px-3 py-2 text-xs bg-red-500/10 text-red-500 border border-red-500/30 rounded hover:bg-red-500/20 transition-colors">
                  Close Position
                </button>
              </div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
