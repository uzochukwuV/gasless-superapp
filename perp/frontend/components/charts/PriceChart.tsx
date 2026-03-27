'use client';

import { useMemo } from 'react';
import {
  ComposedChart,
  Bar,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
} from 'recharts';
import { OHLCV } from '@/hooks/usePriceData';
import { formatNumber } from '@/lib/formatters';

interface PriceChartProps {
  data: OHLCV[];
  currentPrice: number;
  liquidationPrice?: number;
  entryPrice?: number;
  isLong?: boolean;
  height?: number;
}

/**
 * Interactive price chart with entry and liquidation price markers
 */
export default function PriceChart({
  data,
  currentPrice,
  liquidationPrice,
  entryPrice,
  isLong = true,
  height = 400,
}: PriceChartProps) {
  const chartData = useMemo(() => {
    return data.map((candle) => ({
      time: new Date(candle.time * 1000).toLocaleTimeString('en-US', {
        hour: '2-digit',
        minute: '2-digit',
      }),
      open: candle.open,
      high: candle.high,
      low: candle.low,
      close: candle.close,
      volume: candle.volume,
    }));
  }, [data]);

  const yAxisDomain = useMemo(() => {
    if (data.length === 0) return [0, 100];
    const prices = data.flatMap((c) => [c.low, c.high]);
    const min = Math.min(...prices);
    const max = Math.max(...prices);
    const padding = (max - min) * 0.1;
    return [Math.max(0, min - padding), max + padding];
  }, [data]);

  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-black/80 border border-border rounded p-3 shadow-lg">
          <p className="text-xs text-muted-foreground">{data.time}</p>
          <p className="text-sm font-mono text-foreground">
            Open: ${formatNumber(data.open, 2)}
          </p>
          <p className="text-sm font-mono text-foreground">
            High: ${formatNumber(data.high, 2)}
          </p>
          <p className="text-sm font-mono text-foreground">
            Low: ${formatNumber(data.low, 2)}
          </p>
          <p className="text-sm font-mono font-semibold text-foreground">
            Close: ${formatNumber(data.close, 2)}
          </p>
        </div>
      );
    }
    return null;
  };

  return (
    <div className="w-full h-full flex flex-col">
      {/* Price Display */}
      <div className="px-4 py-3 border-b border-border">
        <div className="flex items-baseline gap-2">
          <span className="text-2xl font-bold font-mono">${formatNumber(currentPrice, 2)}</span>
          <span className="text-xs text-muted-foreground">
            {data.length > 0
              ? `${((currentPrice / data[0].open - 1) * 100).toFixed(2)}%`
              : 'N/A'}
          </span>
        </div>
      </div>

      {/* Chart */}
      <div className="flex-1 overflow-hidden">
        <ResponsiveContainer width="100%" height="100%">
          <ComposedChart data={chartData} margin={{ top: 20, right: 30, left: 0, bottom: 20 }}>
            <defs>
              <linearGradient id="volumeGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="rgb(100, 150, 255)" stopOpacity={0.3} />
                <stop offset="95%" stopColor="rgb(100, 150, 255)" stopOpacity={0} />
              </linearGradient>
            </defs>

            <CartesianGrid
              strokeDasharray="3 3"
              stroke="rgb(60, 60, 80)"
              vertical={true}
              horizontalPoints={[]}
            />

            <XAxis
              dataKey="time"
              stroke="rgb(150, 150, 170)"
              tick={{ fontSize: 12, fill: 'rgb(150, 150, 170)' }}
            />

            <YAxis
              domain={yAxisDomain}
              stroke="rgb(150, 150, 170)"
              tick={{ fontSize: 12, fill: 'rgb(150, 150, 170)' }}
              width={60}
            />

            <Tooltip content={<CustomTooltip />} />

            {/* Volume Bars */}
            <Bar dataKey="volume" fill="url(#volumeGradient)" yAxisId="right" />

            {/* Close Price Line */}
            <Line
              type="monotone"
              dataKey="close"
              stroke="rgb(100, 150, 255)"
              dot={false}
              strokeWidth={2}
              isAnimationActive={false}
            />

            {/* Entry Price Line */}
            {entryPrice && (
              <ReferenceLine
                y={entryPrice}
                stroke={isLong ? 'rgb(34, 197, 94)' : 'rgb(239, 68, 68)'}
                strokeDasharray="5 5"
                label={{
                  value: `Entry: $${formatNumber(entryPrice, 2)}`,
                  position: 'right',
                  fill: isLong ? 'rgb(34, 197, 94)' : 'rgb(239, 68, 68)',
                  fontSize: 11,
                }}
              />
            )}

            {/* Liquidation Price Line */}
            {liquidationPrice && (
              <ReferenceLine
                y={liquidationPrice}
                stroke="rgb(239, 68, 68)"
                strokeDasharray="3 3"
                label={{
                  value: `Liquidation: $${formatNumber(liquidationPrice, 2)}`,
                  position: 'right',
                  fill: 'rgb(239, 68, 68)',
                  fontSize: 11,
                  fontWeight: 'bold',
                }}
              />
            )}
          </ComposedChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
