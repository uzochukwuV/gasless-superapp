'use client';

import { useState, useEffect } from 'react';
import dynamic from 'next/dynamic';
import { formatNumber } from '@/lib/formatters';
import { usePriceData } from '@/hooks/usePriceData';
import { CHART_TIMEFRAMES } from '@/lib/constants';

// Dynamically import chart to avoid SSR issues
const PriceChart = dynamic(() => import('@/components/charts/PriceChart'), {
  ssr: false,
  loading: () => <div className="flex items-center justify-center h-full text-muted-foreground">Loading chart...</div>,
});

interface LeftPanelPriceChartProps {
  selectedPair: string;
  currentPrice: number;
  onPriceUpdate?: (price: number) => void;
}

export default function LeftPanelPriceChart({
  selectedPair,
  currentPrice,
  onPriceUpdate,
}: LeftPanelPriceChartProps) {
  const [timeframe, setTimeframe] = useState('1h');
  const { data: chartData, currentPrice: chartPrice, isLoading } = usePriceData({
    pair: selectedPair,
    timeframe,
  });
  const [priceChange, setPriceChange] = useState(0);
  const [priceChangePercent, setPriceChangePercent] = useState(0);

  // Simulate price updates
  useEffect(() => {
    const interval = setInterval(() => {
      const change = (Math.random() - 0.5) * 200;
      const newPrice = currentPrice + change;
      const pc = newPrice - currentPrice;
      setPriceChange(pc);
      setPriceChangePercent((pc / currentPrice) * 100);
      onPriceUpdate?.(newPrice);
    }, 3000);

    return () => clearInterval(interval);
  }, [currentPrice, onPriceUpdate]);

  const handleTimeframeChange = (tf: string) => {
    setChartLoading(true);
    setTimeframe(tf);
    setTimeout(() => setChartLoading(false), 300);
  };

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="border-b border-border p-4">
        <div className="space-y-3">
          {/* Pair & Price Info */}
          <div className="space-y-1">
            <div className="text-lg font-semibold">{selectedPair}</div>
            <div className="flex items-baseline gap-3">
              <div className="text-3xl font-bold font-mono">
                ${formatNumber(currentPrice, 2)}
              </div>
              <div className={`text-sm font-semibold ${priceChange >= 0 ? 'text-green-500' : 'text-red-500'}`}>
                {priceChange >= 0 ? '+' : ''}{formatNumber(priceChange, 2)} ({priceChangePercent >= 0 ? '+' : ''}{priceChangePercent.toFixed(2)}%)
              </div>
            </div>
          </div>

          {/* Timeframe Selector */}
          <div className="flex gap-1 flex-wrap">
            {CHART_TIMEFRAMES.map((tf) => (
              <button
                key={tf.value}
                onClick={() => handleTimeframeChange(tf.value)}
                className={`px-3 py-1 text-xs rounded font-medium transition-colors ${
                  timeframe === tf.value
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-black/20 text-muted-foreground hover:text-foreground'
                }`}
              >
                {tf.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Interactive Price Chart */}
      <div className="flex-1 border-b border-border">
        {chartData.length > 0 ? (
          <PriceChart
            data={chartData}
            currentPrice={chartPrice || currentPrice}
            entryPrice={45000}
            liquidationPrice={38000}
            isLong={true}
            height={300}
          />
        ) : (
          <div className="flex items-center justify-center h-full">
            <div className="text-muted-foreground text-sm">Loading chart data...</div>
          </div>
        )}
      </div>

      {/* Footer - Volume/Stats */}
      <div className="border-t border-border p-4">
        <div className="grid grid-cols-3 gap-3 text-xs">
          <div>
            <div className="text-muted-foreground">24H High</div>
            <div className="font-mono text-foreground">${formatNumber(currentPrice * 1.05, 2)}</div>
          </div>
          <div>
            <div className="text-muted-foreground">24H Low</div>
            <div className="font-mono text-foreground">${formatNumber(currentPrice * 0.95, 2)}</div>
          </div>
          <div>
            <div className="text-muted-foreground">24H Vol</div>
            <div className="font-mono text-foreground">12.3M</div>
          </div>
        </div>
      </div>
    </div>
  );
}
