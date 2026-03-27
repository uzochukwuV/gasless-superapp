'use client';

import { useState } from 'react';
import { useMarginManagement } from '@/hooks/useMarginManagement';
import { formatNumber } from '@/lib/formatters';

interface WithdrawMarginModalProps {
  isOpen: boolean;
  onClose: () => void;
  availableMargin?: number;
  onSuccess?: () => void;
}

export default function WithdrawMarginModal({
  isOpen,
  onClose,
  availableMargin = 25000,
  onSuccess,
}: WithdrawMarginModalProps) {
  const { withdrawMargin, isLoading, error } = useMarginManagement();
  const [amount, setAmount] = useState(1000);
  const [isWithdrawing, setIsWithdrawing] = useState(false);

  if (!isOpen) return null;

  const handleWithdraw = async () => {
    if (amount <= 0 || amount > availableMargin) return;

    setIsWithdrawing(true);
    try {
      const result = await withdrawMargin(BigInt(Math.floor(amount * 1e6)));
      if (result.success) {
        onSuccess?.();
        onClose();
        setAmount(1000);
      }
    } finally {
      setIsWithdrawing(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-background border border-border rounded-lg max-w-md w-full p-6 space-y-6">
        {/* Header */}
        <div className="flex justify-between items-center">
          <h2 className="text-xl font-bold">Withdraw Margin</h2>
          <button
            onClick={onClose}
            className="text-muted-foreground hover:text-foreground transition-colors"
          >
            ✕
          </button>
        </div>

        {/* Available Warning */}
        <div className="bg-yellow-500/10 border border-yellow-500/30 rounded p-3">
          <p className="text-xs text-yellow-400 font-semibold mb-1">Withdrawal Rules</p>
          <p className="text-xs text-muted-foreground">
            You can only withdraw unused margin. Amount in active positions cannot be withdrawn.
          </p>
        </div>

        {/* Amount Input */}
        <div>
          <label className="text-xs text-muted-foreground font-semibold block mb-2">
            Amount (USDC)
          </label>
          <input
            type="number"
            value={amount}
            onChange={(e) => {
              const val = parseFloat(e.target.value) || 0;
              setAmount(Math.min(val, availableMargin));
            }}
            disabled={isWithdrawing}
            className="trading-input text-lg"
            placeholder="Enter amount"
            min="1"
            max={availableMargin}
            step="100"
          />
          <div className="text-xs text-muted-foreground mt-2">
            Available to withdraw: ${formatNumber(availableMargin, 2)}
          </div>
        </div>

        {/* Margin Summary */}
        <div className="bg-black/30 rounded p-3 space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Available Balance</span>
            <span className="font-mono font-semibold">${formatNumber(availableMargin, 2)}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Withdraw Amount</span>
            <span className="font-mono font-semibold text-red-500">-${formatNumber(amount, 2)}</span>
          </div>
          <div className="flex justify-between text-sm border-t border-border/50 pt-2">
            <span className="text-muted-foreground">Remaining Balance</span>
            <span className="font-mono font-semibold">
              ${formatNumber(Math.max(0, availableMargin - amount), 2)}
            </span>
          </div>
        </div>

        {/* Quick Select Buttons */}
        <div className="grid grid-cols-4 gap-2">
          {[250, 500, 1000, 'MAX'].map((preset) => (
            <button
              key={preset}
              onClick={() => {
                if (preset === 'MAX') {
                  setAmount(availableMargin);
                } else if (typeof preset === 'number') {
                  setAmount(Math.min(preset, availableMargin));
                }
              }}
              className="px-2 py-1 text-xs bg-black/30 text-muted-foreground hover:text-foreground rounded transition-colors"
            >
              {preset}
            </button>
          ))}
        </div>

        {/* Error */}
        {error && (
          <div className="bg-red-500/10 border border-red-500/30 rounded p-2 text-xs text-red-500">
            {error}
          </div>
        )}

        {/* Actions */}
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={onClose}
            disabled={isWithdrawing}
            className="px-4 py-2 border border-border rounded font-medium text-sm hover:bg-black/20 transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleWithdraw}
            disabled={isWithdrawing || isLoading || amount <= 0 || amount > availableMargin}
            className="px-4 py-2 bg-red-600 text-white rounded font-medium text-sm hover:bg-red-700 transition-colors disabled:opacity-50"
          >
            {isWithdrawing || isLoading ? 'Withdrawing...' : 'Withdraw'}
          </button>
        </div>
      </div>
    </div>
  );
}
