'use client';

interface LeverageSliderProps {
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  disabled?: boolean;
}

export default function LeverageSlider({
  value,
  onChange,
  min = 1,
  max = 100,
  disabled = false,
}: LeverageSliderProps) {
  const percentage = ((value - min) / (max - min)) * 100;

  // Risk color based on leverage
  const getRiskColor = () => {
    if (value <= 10) return 'accent-green-500';
    if (value <= 25) return 'accent-yellow-500';
    return 'accent-red-500';
  };

  const getRiskLabel = () => {
    if (value <= 10) return 'Low Risk';
    if (value <= 25) return 'Medium Risk';
    return 'High Risk';
  };

  return (
    <div className="space-y-2">
      {/* Slider */}
      <div className="space-y-2">
        <input
          type="range"
          min={min}
          max={max}
          value={value}
          onChange={(e) => onChange(parseFloat(e.target.value))}
          disabled={disabled}
          className={`trading-input h-2 rounded-full appearance-none cursor-pointer ${getRiskColor()}`}
          style={{
            background: `linear-gradient(to right, 
              ${value <= 10 ? '#22c55e' : value <= 25 ? '#eab308' : '#ef4444'} 0%, 
              ${value <= 10 ? '#22c55e' : value <= 25 ? '#eab308' : '#ef4444'} ${percentage}%, 
              rgb(40, 40, 60) ${percentage}%, 
              rgb(40, 40, 60) 100%)`,
          }}
        />
      </div>

      {/* Input Field */}
      <div className="flex items-center gap-2">
        <input
          type="number"
          value={value}
          onChange={(e) => {
            const val = parseFloat(e.target.value);
            if (val >= min && val <= max) {
              onChange(val);
            }
          }}
          disabled={disabled}
          min={min}
          max={max}
          step="1"
          className="w-16 px-2 py-1 text-center bg-input border border-border rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-ring disabled:opacity-50"
        />
        <span className="text-sm text-muted-foreground">x</span>
      </div>

      {/* Risk Indicator */}
      <div className="flex justify-between items-center text-xs">
        <span className={`font-semibold ${
          value <= 10 ? 'text-green-500' : value <= 25 ? 'text-yellow-500' : 'text-red-500'
        }`}>
          {getRiskLabel()}
        </span>
        <span className="text-muted-foreground">
          {value === max ? `Max: ${max}x` : `Range: ${min}x - ${max}x`}
        </span>
      </div>

      {/* Preset Buttons */}
      <div className="grid grid-cols-4 gap-2 pt-2">
        {[1, 5, 10, 25].map((preset) => (
          <button
            key={preset}
            onClick={() => preset <= max && onChange(preset)}
            disabled={disabled || preset > max}
            className={`px-2 py-1 text-xs rounded font-medium transition-colors ${
              value === preset
                ? 'bg-primary text-primary-foreground'
                : 'bg-black/30 text-muted-foreground hover:text-foreground disabled:opacity-50 disabled:cursor-not-allowed'
            }`}
          >
            {preset}x
          </button>
        ))}
      </div>
    </div>
  );
}
