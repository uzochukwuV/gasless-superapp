'use client';

import { useCallback, useState } from 'react';
import { useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { CONTRACTS, MARGIN_ISOLATED, MARGIN_CROSS } from '@/lib/constants';
import { useContractInteraction } from './useContractInteraction';

export interface OpenPositionParams {
  pairId: string;
  margin: bigint;
  leverage: number;
  isLong: boolean;
  stopLoss?: bigint;
  takeProfit?: bigint;
  marginMode?: 'ISOLATED' | 'CROSS';
}

export interface ClosePositionParams {
  positionId: string;
  partialAmount?: bigint;
  closePrice?: bigint;
}

export function usePerpetualTrading() {
  const { executeTransaction } = useContractInteraction();
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Request to open a position (2-step MEV protection)
   * Step 1: Create pending trade
   */
  const requestOpenPosition = useCallback(
    async (params: OpenPositionParams) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Requesting open position:', params);

        const marginMode =
          params.marginMode === 'CROSS' ? MARGIN_CROSS : MARGIN_ISOLATED;

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_trading::request_open_position`,
            arguments: [
              tx.object(CONTRACTS.PERP_STATE_ID),
              tx.pure.string(params.pairId),
              tx.pure.u64(params.margin),
              tx.pure.u16(params.leverage),
              tx.pure.bool(params.isLong),
              tx.pure.u8(marginMode),
            ],
          });
        });

        if (result.success && result.digest) {
          console.log('[v0] Pending trade created:', result.digest);
          return { success: true, tradeId: result.digest, digest: result.digest };
        }

        throw new Error(result.error || 'Failed to request position');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Error requesting position:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Execute pending position opening (2-step MEV protection)
   * Step 2: Execute with oracle price
   */
  const executeOpenPosition = useCallback(
    async (tradeId: string, oraclePrice: bigint) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Executing position with trade ID:', tradeId);

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_trading::execute_pending_trade`,
            arguments: [
              tx.object(CONTRACTS.PERP_STATE_ID),
              tx.pure.string(tradeId),
              tx.pure.u64(oraclePrice),
            ],
          });
        });

        if (result.success && result.digest) {
          console.log('[v0] Position executed:', result.digest);
          return { success: true, positionId: tradeId, digest: result.digest };
        }

        throw new Error(result.error || 'Failed to execute position');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Error executing position:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Open position directly (single-step, higher slippage)
   */
  const openPositionDirect = useCallback(
    async (params: OpenPositionParams) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Opening position directly:', params);

        const marginMode =
          params.marginMode === 'CROSS' ? MARGIN_CROSS : MARGIN_ISOLATED;

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_trading::open_position_direct`,
            arguments: [
              tx.object(CONTRACTS.PERP_STATE_ID),
              tx.pure.string(params.pairId),
              tx.pure.u64(params.margin),
              tx.pure.u16(params.leverage),
              tx.pure.bool(params.isLong),
              tx.pure.u8(marginMode),
              params.stopLoss ? tx.pure.option('u64', params.stopLoss) : tx.pure.option('u64', null),
              params.takeProfit ? tx.pure.option('u64', params.takeProfit) : tx.pure.option('u64', null),
            ],
          });
        });

        if (result.success && result.digest) {
          console.log('[v0] Position opened:', result.digest);
          return { success: true, positionId: result.digest, digest: result.digest };
        }

        throw new Error(result.error || 'Failed to open position');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Error opening position:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Close an open position
   */
  const closePosition = useCallback(
    async (params: ClosePositionParams) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Closing position:', params);

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_trading::close_position`,
            arguments: [
              tx.object(CONTRACTS.PERP_STATE_ID),
              tx.object(params.positionId),
              params.partialAmount ? tx.pure.u64(params.partialAmount) : tx.pure.option('u64', null),
              params.closePrice ? tx.pure.u64(params.closePrice) : tx.pure.option('u64', null),
            ],
          });
        });

        if (result.success && result.digest) {
          console.log('[v0] Position closed:', result.digest);
          return { success: true, digest: result.digest };
        }

        throw new Error(result.error || 'Failed to close position');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Error closing position:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Update take profit and stop loss
   */
  const updatePositionSettings = useCallback(
    async (
      positionId: string,
      takeProfit?: bigint,
      stopLoss?: bigint
    ) => {
      setIsLoading(true);
      setError(null);

      try {
        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_trading::update_position_settings`,
            arguments: [
              tx.object(CONTRACTS.PERP_STATE_ID),
              tx.object(positionId),
              takeProfit ? tx.pure.option('u64', takeProfit) : tx.pure.option('u64', null),
              stopLoss ? tx.pure.option('u64', stopLoss) : tx.pure.option('u64', null),
            ],
          });
        });

        return { success: result.success, digest: result.digest, error: result.error };
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Add margin to position (increases available margin)
   */
  const addMargin = useCallback(
    async (positionId: string, amount: bigint) => {
      setIsLoading(true);
      setError(null);

      try {
        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_margin::add_margin`,
            arguments: [
              tx.object(CONTRACTS.PERP_STATE_ID),
              tx.object(positionId),
              tx.pure.u64(amount),
            ],
          });
        });

        return { success: result.success, digest: result.digest, error: result.error };
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  return {
    requestOpenPosition,
    executeOpenPosition,
    openPositionDirect,
    closePosition,
    updatePositionSettings,
    addMargin,
    isLoading,
    error,
    setError,
  };
}
