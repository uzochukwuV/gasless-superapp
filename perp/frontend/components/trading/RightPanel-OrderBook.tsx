'use client';

import { useMemo } from 'react';
import { formatNumber } from '@/lib/formatters';

interface Order {
  price: number;
  size: number;
  total: number;
}

interface RightPanelOrderBookProps {
  selectedPair: string;
}

export default function RightPanelOrderBook({ selectedPair }: RightPanelOrderBookProps) {
  // Mock order book data
  const { buyOrders, sellOrders, midPrice } = useMemo(() => {
    const basePrice = 45230;
    
    const buys: Order[] = [
      { price: basePrice - 5, size: 1.2, total: 1.2 * (basePrice - 5) },
      { price: basePrice - 10, size: 2.5, total: 2.5 * (basePrice - 10) },
      { price: basePrice - 15, size: 3.8, total: 3.8 * (basePrice - 15) },
      { price: basePrice - 20, size: 5.2, total: 5.2 * (basePrice - 20) },
      { price: basePrice - 25, size: 6.1, total: 6.1 * (basePrice - 25) },
    ];

    const sells: Order[] = [
      { price: basePrice + 5, size: 1.3, total: 1.3 * (basePrice + 5) },
      { price: basePrice + 10, size: 2.4, total: 2.4 * (basePrice + 10) },
      { price: basePrice + 15, size: 3.7, total: 3.7 * (basePrice + 15) },
      { price: basePrice + 20, size: 5.1, total: 5.1 * (basePrice + 20) },
      { price: basePrice + 25, size: 6.2, total: 6.2 * (basePrice + 25) },
    ];

    return {
      buyOrders: buys,
      sellOrders: sells,
      midPrice: basePrice,
    };
  }, []);

  const maxSize = Math.max(
    ...buyOrders.map((o) => o.size),
    ...sellOrders.map((o) => o.size)
  );

  const getDepthWidth = (size: number) => (size / maxSize) * 100;

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="border-b border-border p-4">
        <div className="flex justify-between items-center">
          <div className="text-sm font-semibold">ORDER BOOK</div>
          <div className="text-xs text-muted-foreground">
            Spread: ${(sellOrders[0]?.price - buyOrders[0]?.price).toFixed(2)}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto">
        {/* Sell Orders (Red, descending) */}
        <div className="border-b border-border">
          <div className="bg-black/20 px-4 py-2 border-b border-border">
            <div className="grid grid-cols-3 gap-2 text-xs text-muted-foreground font-mono">
              <div>Price</div>
              <div className="text-right">Size</div>
              <div className="text-right">Total</div>
            </div>
          </div>
          <div className="divide-y divide-border/50">
            {[...sellOrders].reverse().map((order, i) => (
              <div
                key={`sell-${i}`}
                className="relative px-4 py-2 text-xs font-mono hover:bg-black/30 cursor-pointer transition-colors overflow-hidden"
              >
                {/* Depth visualization background */}
                <div
                  className="absolute inset-y-0 right-0 bg-red-500/10"
                  style={{ width: `${getDepthWidth(order.size)}%` }}
                ></div>

                {/* Content */}
                <div className="relative grid grid-cols-3 gap-2">
                  <div className="text-red-500">${formatNumber(order.price, 2)}</div>
                  <div className="text-right text-foreground">{order.size.toFixed(2)}</div>
                  <div className="text-right text-muted-foreground">${formatNumber(order.total, 0)}</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Mid Price */}
        <div className="sticky top-0 z-10 bg-black/50 border-y border-border px-4 py-3 flex justify-between items-center">
          <div className="text-xs text-muted-foreground">Spread</div>
          <div className="text-lg font-bold font-mono">
            ${formatNumber(midPrice, 2)}
          </div>
          <div className="text-xs text-muted-foreground">
            {sellOrders[0] && buyOrders[0]
              ? `${((sellOrders[0].price - buyOrders[0].price) / midPrice * 100).toFixed(3)}%`
              : 'N/A'}
          </div>
        </div>

        {/* Buy Orders (Green, ascending) */}
        <div>
          <div className="bg-black/20 px-4 py-2 border-b border-border">
            <div className="grid grid-cols-3 gap-2 text-xs text-muted-foreground font-mono">
              <div>Price</div>
              <div className="text-right">Size</div>
              <div className="text-right">Total</div>
            </div>
          </div>
          <div className="divide-y divide-border/50">
            {buyOrders.map((order, i) => (
              <div
                key={`buy-${i}`}
                className="relative px-4 py-2 text-xs font-mono hover:bg-black/30 cursor-pointer transition-colors overflow-hidden"
              >
                {/* Depth visualization background */}
                <div
                  className="absolute inset-y-0 right-0 bg-green-500/10"
                  style={{ width: `${getDepthWidth(order.size)}%` }}
                ></div>

                {/* Content */}
                <div className="relative grid grid-cols-3 gap-2">
                  <div className="text-green-500">${formatNumber(order.price, 2)}</div>
                  <div className="text-right text-foreground">{order.size.toFixed(2)}</div>
                  <div className="text-right text-muted-foreground">${formatNumber(order.total, 0)}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Footer - Info */}
      <div className="border-t border-border p-4 text-xs text-muted-foreground">
        <div className="space-y-1">
          <div className="flex justify-between">
            <span>Total Buy Size</span>
            <span>{buyOrders.reduce((sum, o) => sum + o.size, 0).toFixed(2)}</span>
          </div>
          <div className="flex justify-between">
            <span>Total Sell Size</span>
            <span>{sellOrders.reduce((sum, o) => sum + o.size, 0).toFixed(2)}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
