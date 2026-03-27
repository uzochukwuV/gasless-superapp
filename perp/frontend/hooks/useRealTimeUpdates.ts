'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { getSuiClient } from '@/lib/sui-client';
import { CONTRACTS } from '@/lib/constants';

export interface TransactionEvent {
  type: 'POSITION_OPENED' | 'POSITION_CLOSED' | 'ORDER_FILLED' | 'LIQUIDATION' | 'MARGIN_UPDATED';
  positionId?: string;
  orderId?: string;
  digest: string;
  timestamp: number;
  data?: any;
}

/**
 * Hook for subscribing to real-time contract events
 * Uses Sui event subscriptions for live updates
 */
export function useRealTimeUpdates() {
  const [events, setEvents] = useState<TransactionEvent[]>([]);
  const [isConnected, setIsConnected] = useState(false);
  const subscriptionIdRef = useRef<number | null>(null);

  /**
   * Subscribe to contract events
   */
  const subscribe = useCallback(async () => {
    try {
      const client = getSuiClient();

      // Subscribe to all events from perpetual module
      subscriptionIdRef.current = await client.subscribeEvent({
        filter: {
          MoveModule: {
            package: CONTRACTS.PACKAGE_ID,
            module: 'perp_trading',
          },
        },
        onMessage: (event: any) => {
          console.log('[v0] Event received:', event);

          const txEvent: TransactionEvent = {
            type: 'POSITION_OPENED',
            digest: event.id?.txDigest || '',
            timestamp: Date.now(),
            data: event.parsedJson,
          };

          // Parse event type from event struct name
          if (event.type?.includes('PositionOpened')) {
            txEvent.type = 'POSITION_OPENED';
          } else if (event.type?.includes('PositionClosed')) {
            txEvent.type = 'POSITION_CLOSED';
          } else if (event.type?.includes('OrderFilled')) {
            txEvent.type = 'ORDER_FILLED';
          } else if (event.type?.includes('Liquidation')) {
            txEvent.type = 'LIQUIDATION';
          }

          setEvents((prev) => [txEvent, ...prev.slice(0, 99)]);
        },
        onError: (error: any) => {
          console.error('[v0] Event subscription error:', error);
          setIsConnected(false);
        },
      });

      setIsConnected(true);
      console.log('[v0] Subscribed to real-time events');
    } catch (error) {
      console.error('[v0] Failed to subscribe to events:', error);
      setIsConnected(false);
    }
  }, []);

  /**
   * Unsubscribe from events
   */
  const unsubscribe = useCallback(() => {
    if (subscriptionIdRef.current !== null) {
      // In production, properly unsubscribe from the client
      subscriptionIdRef.current = null;
      setIsConnected(false);
      console.log('[v0] Unsubscribed from events');
    }
  }, []);

  /**
   * Polling fallback for events (when WebSocket subscription fails)
   */
  useEffect(() => {
    if (!isConnected) {
      // Optional: Implement polling as fallback
      const pollInterval = setInterval(() => {
        // Poll for new events
      }, 5000);

      return () => clearInterval(pollInterval);
    }
  }, [isConnected]);

  /**
   * Auto-subscribe on mount
   */
  useEffect(() => {
    subscribe();

    return () => {
      unsubscribe();
    };
  }, [subscribe, unsubscribe]);

  /**
   * Listen for specific event type
   */
  const onEvent = useCallback(
    (eventType: TransactionEvent['type'], callback: (event: TransactionEvent) => void) => {
      const handleEvent = (event: TransactionEvent) => {
        if (event.type === eventType) {
          callback(event);
        }
      };

      // Filter existing events
      events.forEach((event) => {
        if (event.type === eventType) {
          callback(event);
        }
      });

      // Set up listener for new events
      const unlistener = () => {
        // Cleanup
      };

      return unlistener;
    },
    [events]
  );

  /**
   * Clear events history
   */
  const clearEvents = useCallback(() => {
    setEvents([]);
  }, []);

  return {
    events,
    isConnected,
    subscribe,
    unsubscribe,
    onEvent,
    clearEvents,
  };
}
