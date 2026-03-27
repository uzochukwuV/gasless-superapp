'use client';

import { useRealTimeUpdates, TransactionEvent } from '@/hooks/useRealTimeUpdates';
import { formatDateTime, formatTxHash } from '@/lib/formatters';

export default function TransactionHistory() {
  const { events } = useRealTimeUpdates();

  const getEventIcon = (type: TransactionEvent['type']) => {
    switch (type) {
      case 'POSITION_OPENED':
        return '📈';
      case 'POSITION_CLOSED':
        return '📉';
      case 'ORDER_FILLED':
        return '✓';
      case 'LIQUIDATION':
        return '⚠️';
      case 'MARGIN_UPDATED':
        return '💰';
      default:
        return '•';
    }
  };

  const getEventColor = (type: TransactionEvent['type']) => {
    switch (type) {
      case 'POSITION_OPENED':
        return 'text-green-500';
      case 'POSITION_CLOSED':
        return 'text-blue-500';
      case 'ORDER_FILLED':
        return 'text-purple-500';
      case 'LIQUIDATION':
        return 'text-red-500';
      case 'MARGIN_UPDATED':
        return 'text-yellow-500';
      default:
        return 'text-muted-foreground';
    }
  };

  if (events.length === 0) {
    return (
      <div className="text-center py-4">
        <div className="text-xs text-muted-foreground">No recent transactions</div>
      </div>
    );
  }

  return (
    <div className="space-y-2 max-h-48 overflow-y-auto">
      {events.slice(0, 10).map((event, index) => (
        <div
          key={index}
          className="flex items-start justify-between p-2 bg-black/20 rounded text-xs hover:bg-black/30 transition-colors"
        >
          <div className="flex items-start gap-2 flex-1">
            <span className="text-lg">{getEventIcon(event.type)}</span>
            <div className="flex-1">
              <div className={`font-semibold ${getEventColor(event.type)}`}>
                {event.type.replace(/_/g, ' ')}
              </div>
              <div className="text-muted-foreground text-xs mt-1">
                {formatDateTime(Math.floor(event.timestamp / 1000))}
              </div>
            </div>
          </div>
          <div className="text-muted-foreground hover:text-foreground cursor-pointer transition-colors">
            {formatTxHash(event.digest, 4)}
          </div>
        </div>
      ))}
    </div>
  );
}
