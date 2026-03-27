'use client';

import { useCallback, useEffect, useState } from 'react';
import { Order } from '@/types/trading';
import { useContractInteraction } from './useContractInteraction';
import { CONTRACTS } from '@/lib/constants';

export interface OrderBookData {
  buyOrders: Order[];
  sellOrders: Order[];
  midPrice: number;
  spread: number;
}

/**
 * Hook for managing limit orders and order book data
 */
export function useOrderBook(pair: string) {
  const { executeTransaction } = useContractInteraction();
  const [orderBook, setOrderBook] = useState<OrderBookData>({
    buyOrders: [],
    sellOrders: [],
    midPrice: 0,
    spread: 0,
  });
  const [userOrders, setUserOrders] = useState<Order[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  /**
   * Fetch order book data
   */
  const fetchOrderBook = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      console.log('[v0] Fetching order book for:', pair);

      // In production, fetch from contract
      // This would use getSuiClient().getDynamicFields()
      // to read the OrderBook object

      // Mock data for demo
      const basePrice = 45230;
      const mockBuyOrders: Order[] = [
        {
          id: '1',
          owner: '0x123',
          pairId: pair,
          orderType: 'LIMIT',
          direction: 'BUY',
          size: 1n,
          price: BigInt(Math.floor((basePrice - 5) * 1e10)),
          leverage: 1,
          margin: 1000000000n,
          status: 'OPEN',
          createdAt: Math.floor(Date.now() / 1000),
          expiresAt: Math.floor(Date.now() / 1000) + 86400,
        },
      ];

      const mockSellOrders: Order[] = [
        {
          id: '2',
          owner: '0x456',
          pairId: pair,
          orderType: 'LIMIT',
          direction: 'SELL',
          size: 1n,
          price: BigInt(Math.floor((basePrice + 5) * 1e10)),
          leverage: 1,
          margin: 1000000000n,
          status: 'OPEN',
          createdAt: Math.floor(Date.now() / 1000),
          expiresAt: Math.floor(Date.now() / 1000) + 86400,
        },
      ];

      setOrderBook({
        buyOrders: mockBuyOrders,
        sellOrders: mockSellOrders,
        midPrice: basePrice,
        spread: 10,
      });

      console.log('[v0] Order book loaded');
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to fetch order book';
      setError(errorMsg);
      console.error('[v0] Error fetching order book:', errorMsg);
    } finally {
      setIsLoading(false);
    }
  }, [pair]);

  /**
   * Place a limit order
   */
  const placeLimitOrder = useCallback(
    async (params: {
      pair: string;
      price: bigint;
      size: bigint;
      leverage: number;
      margin: bigint;
      isLong: boolean;
      expiresIn?: number;
    }) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Placing limit order:', params);

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_orderbook::place_limit_order`,
            arguments: [
              tx.object(CONTRACTS.ORDER_BOOK_ID),
              tx.pure.string(params.pair),
              tx.pure.u64(params.price),
              tx.pure.u64(params.size),
              tx.pure.u16(params.leverage),
              tx.pure.u64(params.margin),
              tx.pure.bool(params.isLong),
              tx.pure.u64(params.expiresIn || 86400),
            ],
          });
        });

        if (result.success) {
          // Refresh order book
          fetchOrderBook();
          console.log('[v0] Order placed successfully');
          return { success: true, digest: result.digest };
        }

        throw new Error(result.error || 'Failed to place order');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Error placing order:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction, fetchOrderBook]
  );

  /**
   * Cancel an order
   */
  const cancelOrder = useCallback(
    async (orderId: string) => {
      setIsLoading(true);
      setError(null);

      try {
        console.log('[v0] Cancelling order:', orderId);

        const result = await executeTransaction((tx) => {
          tx.moveCall({
            target: `${CONTRACTS.PACKAGE_ID}::perp_orderbook::cancel_order`,
            arguments: [
              tx.object(CONTRACTS.ORDER_BOOK_ID),
              tx.object(orderId),
            ],
          });
        });

        if (result.success) {
          // Remove from user orders
          setUserOrders((prev) => prev.filter((o) => o.id !== orderId));
          console.log('[v0] Order cancelled');
          return { success: true };
        }

        throw new Error(result.error || 'Failed to cancel order');
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        setError(errorMsg);
        console.error('[v0] Error cancelling order:', errorMsg);
        return { success: false, error: errorMsg };
      } finally {
        setIsLoading(false);
      }
    },
    [executeTransaction]
  );

  /**
   * Fetch user's orders
   */
  const fetchUserOrders = useCallback(async () => {
    try {
      // In production, filter orders by user address
      console.log('[v0] Fetching user orders');
      // setUserOrders(...);
    } catch (err) {
      console.error('[v0] Error fetching user orders:', err);
    }
  }, []);

  // Auto-fetch on mount and when pair changes
  useEffect(() => {
    fetchOrderBook();
  }, [fetchOrderBook]);

  return {
    orderBook,
    userOrders,
    isLoading,
    error,
    fetchOrderBook,
    fetchUserOrders,
    placeLimitOrder,
    cancelOrder,
  };
}
