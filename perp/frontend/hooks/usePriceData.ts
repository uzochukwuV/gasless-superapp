'use client';

import { useCallback, useEffect, useState } from 'react';
import { CHART_TIMEFRAMES } from '@/lib/constants';

export interface OHLCV {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

interface UsePriceDataProps {
  pair: string;
  timeframe?: string;
}

/**
 * Hook for fetching and managing price chart data
 * In production, this would fetch from oracle or price API
 */
export function usePriceData({ pair, timeframe = '1h' }: UsePriceDataProps) {
  const [data, setData] = useState<OHLCV[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentPrice, setCurrentPrice] = useState<number>(0);

  /**
   * Generate mock OHLCV data for demo
   * Replace with real oracle data in production
   */
  const generateMockData = useCallback((pair: string, count: number = 100): OHLCV[] => {
    const basePrices: Record<string, number> = {
      'BTC/USD': 45230,
      'ETH/USD': 2350,
      'SOL/USD': 145,
      'USDT/USD': 1.0,
    };

    const basePrice = basePrices[pair] || 50000;
    const data: OHLCV[] = [];
    let currentPrice = basePrice;

    const now = Math.floor(Date.now() / 1000);
    const intervalSeconds = timeframe === '1m' ? 60 : timeframe === '5m' ? 300 : timeframe === '15m' ? 900 : timeframe === '1h' ? 3600 : timeframe === '4h' ? 14400 : 86400;

    for (let i = count - 1; i >= 0; i--) {
      const change = (Math.random() - 0.5) * basePrice * 0.02; // 2% volatility
      currentPrice += change;

      const open = currentPrice;
      const close = currentPrice + (Math.random() - 0.5) * basePrice * 0.01;
      const high = Math.max(open, close) + Math.random() * basePrice * 0.005;
      const low = Math.min(open, close) - Math.random() * basePrice * 0.005;

      data.push({
        time: now - i * intervalSeconds,
        open,
        high,
        low,
        close,
        volume: Math.random() * 1000000,
      });
    }

    return data;
  }, [timeframe]);

  /**
   * Fetch price data for given pair and timeframe
   */
  const fetchPriceData = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      // Simulate API delay
      await new Promise((resolve) => setTimeout(resolve, 300));

      const chartData = generateMockData(pair, 100);
      setData(chartData);
      setCurrentPrice(chartData[chartData.length - 1].close);

      console.log('[v0] Price data loaded:', pair, timeframe);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to load price data';
      setError(errorMsg);
      console.error('[v0] Error loading price data:', errorMsg);
    } finally {
      setIsLoading(false);
    }
  }, [pair, timeframe, generateMockData]);

  // Load data on mount and when pair/timeframe changes
  useEffect(() => {
    fetchPriceData();
  }, [fetchPriceData]);

  /**
   * Simulate real-time price updates
   */
  useEffect(() => {
    if (data.length === 0) return;

    const interval = setInterval(() => {
      setData((prev) => {
        if (prev.length === 0) return prev;

        const lastCandle = prev[prev.length - 1];
        const change = (Math.random() - 0.5) * lastCandle.close * 0.002;
        const newClose = lastCandle.close + change;

        return [
          ...prev.slice(0, -1),
          {
            ...lastCandle,
            close: newClose,
            high: Math.max(lastCandle.high, newClose),
            low: Math.min(lastCandle.low, newClose),
          },
        ];
      });

      setCurrentPrice(data[data.length - 1].close);
    }, 1000);

    return () => clearInterval(interval);
  }, [data]);

  return {
    data,
    currentPrice,
    isLoading,
    error,
    refetch: fetchPriceData,
  };
}
