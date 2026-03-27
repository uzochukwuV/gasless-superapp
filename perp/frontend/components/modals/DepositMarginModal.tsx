'use client';

import { useState } from 'react';
import { useMarginManagement } from '@/hooks/useMarginManagement';
import { formatNumber } from '@/lib/formatters';

interface DepositMarginModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

export default function DepositMarginModal({
  isOpen,
  onClose,
  onSuccess,
}: DepositMarginModalProps) {
  const { depositMargin, isLoading, error } = useMarginManagement();
  const [amount, setAmount] = useState(1000);
  const [isDepositing, setIsDepositing] = useState(false);

  if (!isOpen) return null;

  const handleDeposit = async () => {
    if (amount <= 0) return;

    setIsDepositing(true);
    try {
      const result = await depositMargin(BigInt(Math.floor(amount * 1e6)));
      if (result.success) {
        onSuccess?.();
        onClose();
        setAmount(1000);
      }
    } finally {
      setIsDepositing(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-background border border-border rounded-lg max-w-md w-full p-6 space-y-6">
        {/* Header */}
        <div className="flex justify-between items-center">
          <h2 className="text-xl font-bold">Deposit Margin</h2>
          <button
            onClick={onClose}
            className="text-muted-foreground hover:text-foreground transition-colors"
          >
            ✕
          </button>
        </div>

        {/* Amount Input */}
        <div>
          <label className="text-xs text-muted-foreground font-semibold block mb-2">
            Amount (USDC)
          </label>
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(Math.max(0, parseFloat(e.target.value) || 0))}
            disabled={isDepositing}
            className="trading-input text-lg"
            placeholder="Enter amount"
            min="1"
            step="100"
          />
        </div>

        {/* Available Balance */}
        <div className="bg-black/30 rounded p-3 space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Available Balance</span>
            <span className="font-mono font-semibold">$100,000 USDC</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Deposit Amount</span>
            <span className="font-mono font-semibold text-green-500">+${formatNumber(amount, 2)}</span>
          </div>
          <div className="flex justify-between text-sm border-t border-border/50 pt-2">
            <span className="text-muted-foreground">New Balance</span>
            <span className="font-mono font-semibold">${formatNumber(100000 + amount, 2)}</span>
          </div>
        </div>

        {/* Fee Info */}
        <div className="bg-blue-500/10 border border-blue-500/30 rounded p-3">
          <p className="text-xs text-blue-400 font-medium mb-2">No deposit fees</p>
          <p className="text-xs text-muted-foreground">
            Your deposit will be credited instantly to your trading account.
          </p>
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
            disabled={isDepositing}
            className="px-4 py-2 border border-border rounded font-medium text-sm hover:bg-black/20 transition-colors disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            onClick={handleDeposit}
            disabled={isDepositing || isLoading || amount <= 0}
            className="px-4 py-2 bg-green-600 text-white rounded font-medium text-sm hover:bg-green-700 transition-colors disabled:opacity-50"
          >
            {isDepositing || isLoading ? 'Depositing...' : 'Deposit'}
          </button>
        </div>
      </div>
    </div>
  );
}
