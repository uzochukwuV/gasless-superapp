'use client';

import { useState } from 'react';
import { usePerpetualTrading } from '@/hooks/usePerpetualTrading';
import { formatNumber, getPnLColorClass } from '@/lib/formatters';

interface ClosePositionModalProps {
  isOpen: boolean;
  onClose: () => void;
  position: {
    id: string;
    pair: string;
    isLong: boolean;
    size: number;
    entryPrice: number;
    currentPrice: number;
    pnl: number;
  };
  onSuccess?: () => void;
}

export default function ClosePositionModal({
  isOpen,
  onClose,
  position,
  onSuccess,
}: ClosePositionModalProps) {
  const { closePosition, isLoading, error } = usePerpetualTrading();
  const [closeType, setCloseType] = useState<'market' | 'limit'>('market');
  const [limitPrice, setLimitPrice] = useState(position.currentPrice);
  const [partialSize, setPartialSize] = useState<number | null>(null);
  const [isClosing, setIsClosing] = useState(false);

  if (!isOpen) return null;

  const closingSize = partialSize || position.size;
  const closingValue = closingSize * position.currentPrice;
  const closingPnL = (position.pnl * closingSize) / position.size;

  const handleClose = async () => {
    setIsClosing(true);
    try {
      const result = await closePosition({
        positionId: position.id,
        partialAmount: partialSize ? Math.floor(partialSize * 1e6) : undefined,
        closePrice: closeType === 'limit' ? BigInt(Math.floor(limitPrice * 1e10)) : undefined,
      });

      if (result.success) {
        onSuccess?.();
        onClose();
      }
    } finally {
      setIsClosing(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-background border border-border rounded-lg max-w-md w-full p-6 space-y-6">
        {/* Header */}
        <div className="flex justify-between items-center">
          <h2 className="text-xl font-bold">Close {position.pair}</h2>
          <button
            onClick={onClose}
            className="text-muted-foreground hover:text-foreground transition-colors"
          >
            ✕
          </button>
        </div>

        {/* Position Info */}
        <div className="space-y-2 bg-black/30 rounded p-3">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Position Size</span>
            <span className="font-mono">{position.size.toFixed(4)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Entry Price</span>
            <span className="font-mono">${formatNumber(position.entryPrice, 2)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Current Price</span>
            <span className="font-mono">${formatNumber(position.currentPrice, 2)}</span>
          </div>
          <div className="flex justify-between text-sm border-t border-border/50 pt-2">
            <span className="text-muted-foreground">Current P&L</span>
            <span className={`font-mono font-semibold ${getPnLColorClass(position.pnl)}`}>
              {position.pnl >= 0 ? '+' : ''}{formatNumber(position.pnl, 2)}
            </span>
          </div>
        </div>

        {/* Close Type Selection */}
        <div>
          <label className="text-xs text-muted-foreground font-semibold block mb-2">
            Close Type
          </label>
          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => setCloseType('market')}
              className={`py-2 rounded text-sm font-medium transition-colors ${
                closeType === 'market'
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-black/30 text-muted-foreground hover:text-foreground'
              }`}
            >
              Market
            </button>
            <button
              onClick={() => setCloseType('limit')}
              className={`py-2 rounded text-sm font-medium transition-colors ${
                closeType === 'limit'
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-black/30 text-muted-foreground hover:text-foreground'
              }`}
            >
              Limit
            </button>
          </div>
        </div>

        {/* Limit Price (if limit order) */}
        {closeType === 'limit' && (
          <div>
            <label className="text-xs text-muted-foreground font-semibold block mb-2">
              Limit Price
            </label>
            <input
              type="number"
              value={limitPrice}
              onChange={(e) => setLimitPrice(parseFloat(e.target.value))}
              className="trading-input text-sm"
              disabled={isClosing}
            />
          </div>
        )}

        {/* Partial Close Option */}
        <div>
          <label className="text-xs text-muted-foreground font-semibold block mb-2">
            Close Amount (Optional - Leave empty for full close)
          </label>
          <input
            type="number"
            value={partialSize || ''}
            onChange={(e) => setPartialSize(e.target.value ? parseFloat(e.target.value) : null)}
            max={position.size}
            step="0.0001"
            className="trading-input text-sm"
            placeholder={`Max: ${position.size.toFixed(4)}`}
            disabled={isClosing}
          />
        </div>

        {/* Close Summary */}
        <div className="bg-black/30 rounded p-3 space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Closing Size</span>
            <span className="font-mono">{closingSize.toFixed(4)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Closing Value (USD)</span>
            <span className="font-mono">${formatNumber(closingValue, 2)}</span>
          </div>
          <div className="flex justify-between text-sm border-t border-border/50 pt-2">
            <span className="text-muted-foreground">Expected P&L</span>
            <span className={`font-mono font-semibold ${getPnLColorClass(closingPnL)}`}>
              {closingPnL >= 0 ? '+' : ''}{formatNumber(closingPnL, 2)}
            </span>
          </div>
        </div>

        {/* Error */}
        {(error) && (
          <div className="bg-red-500/10 border border-red-500/30 rounded p-2 text-xs text-red-500">
            {error}
          </div>
        )}

        {/* Actions */}
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={onClose}
            disabled={isClosing}
            className="px-4 py-2 border border-border rounded font-medium text-sm hover:bg-black/20 transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleClose}
            disabled={isClosing || isLoading}
            className="px-4 py-2 bg-red-600 text-white rounded font-medium text-sm hover:bg-red-700 transition-colors disabled:opacity-50"
          >
            {isClosing || isLoading ? 'Closing...' : 'Close Position'}
          </button>
        </div>
      </div>
    </div>
  );
}
