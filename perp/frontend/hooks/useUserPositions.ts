'use client';

import { useCallback, useEffect, useState } from 'react';
import { useWallet } from '@mysten/dapp-kit';
import { Position } from '@/types/trading';
import { calculatePnL, calculateMarginRatio } from '@/lib/contractHelpers';

/**
 * Hook for fetching and managing user's open positions
 */
export function useUserPositions() {
  const { currentAccount } = useWallet();
  const [positions, setPositions] = useState<Position[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Fetch user positions from contract
   */
  const fetchPositions = useCallback(async () => {
    if (!currentAccount) {
      setPositions([]);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      // In production, fetch from Sui blockchain
      // This would be implemented with useSuiClient().getOwnedObjects()
      // with type filter for Position objects

      console.log('[v0] Fetching positions for:', currentAccount.address);

      // Mock data for demo
      const mockPositions: Position[] = [
        {
          id: '0x123abc',
          owner: currentAccount.address,
          pairId: 'BTC/USD',
          isLong: true,
          margin: 10000000000n, // $10,000 USDC
          leverage: 10,
          openPrice: 450000000000000n, // $45,000
          currentPrice: 452300000000000n, // $45,230
          size: 100000000n,
          liquidationPrice: 380000000000000n,
          marginRatio: 75,
          createdAt: Math.floor(Date.now() / 1000) - 86400,
          status: 'OPEN',
        },
      ];

      // Calculate PnL for each position
      const positionsWithPnL = mockPositions.map((pos) => ({
        ...pos,
        pnl: calculatePnL(
          pos.isLong,
          pos.openPrice,
          pos.currentPrice || pos.openPrice,
          pos.size
        ),
        pnlPercentage: 5.1, // Demo value
      }));

      setPositions(positionsWithPnL);
      console.log('[v0] Positions loaded:', positionsWithPnL.length);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to fetch positions';
      setError(errorMsg);
      console.error('[v0] Error fetching positions:', errorMsg);
    } finally {
      setIsLoading(false);
    }
  }, [currentAccount]);

  /**
   * Refresh positions periodically
   */
  useEffect(() => {
    fetchPositions();

    // Refresh every 5 seconds
    const interval = setInterval(fetchPositions, 5000);

    return () => clearInterval(interval);
  }, [fetchPositions]);

  /**
   * Update position after trade
   */
  const addPosition = useCallback((position: Position) => {
    setPositions((prev) => [...prev, position]);
  }, []);

  /**
   * Remove position after close
   */
  const removePosition = useCallback((positionId: string) => {
    setPositions((prev) => prev.filter((p) => p.id !== positionId));
  }, []);

  /**
   * Update position price
   */
  const updatePositionPrice = useCallback((positionId: string, newPrice: bigint) => {
    setPositions((prev) =>
      prev.map((p) =>
        p.id === positionId
          ? {
              ...p,
              currentPrice: newPrice,
              pnl: calculatePnL(p.isLong, p.openPrice, newPrice, p.size),
            }
          : p
      )
    );
  }, []);

  /**
   * Calculate total stats
   */
  const getStats = useCallback(() => {
    const totalMargin = positions.reduce((sum, p) => sum + p.margin, 0n);
    const totalPnL = positions.reduce((sum, p) => sum + (p.pnl || 0n), 0n);
    const totalExposure = positions.reduce(
      (sum, p) => sum + (p.currentPrice ? p.size * p.currentPrice : 0n),
      0n
    );

    return {
      totalMargin,
      totalPnL,
      totalExposure,
      positionCount: positions.length,
      avgLeverage:
        positions.length > 0
          ? positions.reduce((sum, p) => sum + p.leverage, 0) / positions.length
          : 0,
    };
  }, [positions]);

  return {
    positions,
    isLoading,
    error,
    fetchPositions,
    addPosition,
    removePosition,
    updatePositionPrice,
    getStats,
  };
}
