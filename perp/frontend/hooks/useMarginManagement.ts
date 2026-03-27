'use client';

import { useCallback, useState } from 'react';
import { useContractInteraction } from './useContractInteraction';
import { CONTRACTS } from '@/lib/constants';

export interface MarginTransaction {
  amount: bigint;
  type: 'DEPOSIT' | 'WITHDRAW';
  timestamp: number;
  digest?: string;
}

/**
 * Hook for managing margin (deposit/withdraw)
 */
export function useMarginManagement() {
  const { executeTransaction } = useContractInteraction();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [transactions, setTransactions] = useState<MarginTransaction[]>([]);

  /**
   * Deposit margin to account
   */
  const depositMargin = useCallback(
    async (amount: bigint) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Depositing margin:', amount);

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_vault::deposit_collateral`,
            arguments: [
              tx.object(CONTRACTS.VAULT_ID),
              tx.pure.u64(amount),
            ],
          });
        });

        if (result.success && result.digest) {
          const transaction: MarginTransaction = {
            amount,
            type: 'DEPOSIT',
            timestamp: Date.now(),
            digest: result.digest,
          };
          setTransactions((prev) => [transaction, ...prev]);
          console.log('[v0] Deposit successful:', result.digest);
          return { success: true, digest: result.digest };
        }

        throw new Error(result.error || 'Deposit failed');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Deposit error:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Withdraw margin from account
   */
  const withdrawMargin = useCallback(
    async (amount: bigint) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Withdrawing margin:', amount);

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_vault::withdraw_collateral`,
            arguments: [
              tx.object(CONTRACTS.VAULT_ID),
              tx.pure.u64(amount),
            ],
          });
        });

        if (result.success && result.digest) {
          const transaction: MarginTransaction = {
            amount,
            type: 'WITHDRAW',
            timestamp: Date.now(),
            digest: result.digest,
          };
          setTransactions((prev) => [transaction, ...prev]);
          console.log('[v0] Withdrawal successful:', result.digest);
          return { success: true, digest: result.digest };
        }

        throw new Error(result.error || 'Withdrawal failed');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Withdrawal error:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Get margin history
   */
  const getTransactionHistory = useCallback(() => {
    return transactions;
  }, [transactions]);

  /**
   * Clear error
   */
  const clearError = useCallback(() => {
    setError(null);
  }, []);

  return {
    depositMargin,
    withdrawMargin,
    getTransactionHistory,
    isLoading,
    error,
    clearError,
  };
}
