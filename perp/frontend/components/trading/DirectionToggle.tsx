'use client';

interface DirectionToggleProps {
  isLong: boolean;
  onToggle: (isLong: boolean) => void;
}

export default function DirectionToggle({ isLong, onToggle }: DirectionToggleProps) {
  return (
    <div className="grid grid-cols-2 gap-2">
      <button
        onClick={() => onToggle(true)}
        className={`py-3 rounded font-semibold text-sm transition-colors ${
          isLong
            ? 'bg-green-600 text-white shadow-lg'
            : 'bg-black/30 text-muted-foreground hover:text-foreground border border-border'
        }`}
      >
        <div className="flex items-center justify-center gap-2">
          <span>📈</span>
          <span>LONG</span>
        </div>
      </button>
      <button
        onClick={() => onToggle(false)}
        className={`py-3 rounded font-semibold text-sm transition-colors ${
          !isLong
            ? 'bg-red-600 text-white shadow-lg'
            : 'bg-black/30 text-muted-foreground hover:text-foreground border border-border'
        }`}
      >
        <div className="flex items-center justify-center gap-2">
          <span>📉</span>
          <span>SHORT</span>
        </div>
      </button>
    </div>
  );
}
