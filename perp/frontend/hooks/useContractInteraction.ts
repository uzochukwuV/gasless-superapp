'use client';

import { useCallback, useState } from 'react';
import { useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { CONTRACTS, TX_TIMEOUT_MS, MAX_RETRIES } from '@/lib/constants';
import { ERROR_MESSAGES } from '@/lib/constants';

export interface TransactionResult {
  digest?: string;
  error?: string;
  success: boolean;
  status?: 'pending' | 'success' | 'failed';
}

export function useContractInteraction() {
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Execute a contract function call
   */
  const executeTransaction = useCallback(
    async (
      txBuilder: (tx: Transaction) => void,
      options?: {
        timeoutMs?: number;
        retries?: number;
        onSuccess?: (digest: string) => void;
        onError?: (error: string) => void;
      }
    ): Promise<TransactionResult> => {
      const timeoutMs = options?.timeoutMs ?? TX_TIMEOUT_MS;
      const maxRetries = options?.retries ?? MAX_RETRIES;

      setIsLoading(true);
      setError(null);

      let lastError: string | undefined;

      for (let attempt = 0; attempt <= maxRetries; attempt++) {
        try {
          const tx = new Transaction();

          // Build transaction with user-provided function
          txBuilder(tx);

          // Set gas budget if not already set
          if (!tx.data.gasData.budget) {
            tx.setGasBudget(1000000000); // 1 SUI
          }

          // Execute transaction
          return await new Promise<TransactionResult>((resolve, reject) => {
            const timeoutId = setTimeout(() => {
              setError('Transaction timeout');
              reject(new Error('Transaction timeout'));
            }, timeoutMs);

            signAndExecute(
              { transaction: tx },
              {
                onSuccess: (result) => {
                  clearTimeout(timeoutId);
                  setIsLoading(false);
                  console.log('[v0] Transaction success:', result);
                  options?.onSuccess?.(result.digest);
                  resolve({ digest: result.digest, success: true, status: 'success' });
                },
                onError: (err: any) => {
                  clearTimeout(timeoutId);
                  const errorMsg = err?.message || 'Unknown error';
                  setError(errorMsg);
                  options?.onError?.(errorMsg);
                  lastError = errorMsg;
                },
              }
            );
          });
        } catch (err) {
          const errorMsg = err instanceof Error ? err.message : String(err);
          lastError = errorMsg;

          // Retry if attempts remaining
          if (attempt < maxRetries) {
            console.log(`[v0] Retry attempt ${attempt + 1}/${maxRetries}`);
            await new Promise((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
            continue;
          }
        }
      }

      setIsLoading(false);
      const finalError = lastError || 'Transaction failed after all retries';
      setError(finalError);
      options?.onError?.(finalError);
      return { error: finalError, success: false, status: 'failed' };
    },
    [signAndExecute]
  );

  /**
   * Call a contract function and return result
   */
  const callContractFunction = useCallback(
    async (
      moduleName: string,
      functionName: string,
      typeArguments: string[] = [],
      arguments_: any[] = []
    ) => {
      return executeTransaction((tx) => {
        tx.moveCall({
          target: `${CONTRACTS.PACKAGE_ID}::${moduleName}::${functionName}`,
          typeArguments,
          arguments: arguments_,
        });
      });
    },
    [executeTransaction]
  );

  /**
   * Parse contract error code to message
   */
  const parseContractError = useCallback((errorCode: number): string => {
    return ERROR_MESSAGES[errorCode] || `Unknown error (code: ${errorCode})`;
  }, []);

  return {
    executeTransaction,
    callContractFunction,
    parseContractError,
    isLoading,
    error,
    setError,
  };
}
