'use client';

import { useState } from 'react';

interface PairSelectorProps {
  selectedPair: string;
  onPairChange: (pair: string) => void;
  pairs: string[];
}

export default function PairSelector({
  selectedPair,
  onPairChange,
  pairs,
}: PairSelectorProps) {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div className="relative">
      {/* Dropdown Button */}
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="trading-input flex justify-between items-center pr-3 text-left"
      >
        <span className="font-semibold">{selectedPair}</span>
        <svg
          className={`w-4 h-4 text-muted-foreground transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
        </svg>
      </button>

      {/* Dropdown Menu */}
      {isOpen && (
        <div className="absolute top-full left-0 right-0 z-50 mt-1 border border-border rounded bg-background shadow-lg">
          {pairs.map((pair) => (
            <button
              key={pair}
              onClick={() => {
                onPairChange(pair);
                setIsOpen(false);
              }}
              className={`w-full text-left px-4 py-2 text-sm transition-colors ${
                selectedPair === pair
                  ? 'bg-primary text-primary-foreground font-semibold'
                  : 'hover:bg-black/30 text-foreground'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="font-medium">{pair}</span>
                <span className="text-xs text-muted-foreground">
                  {Math.random() > 0.5 ? '+' : '-'}{(Math.random() * 5).toFixed(2)}%
                </span>
              </div>
            </button>
          ))}
        </div>
      )}

      {/* Backdrop to close dropdown */}
      {isOpen && (
        <button
          onClick={() => setIsOpen(false)}
          className="fixed inset-0 z-40"
        ></button>
      )}
    </div>
  );
}
