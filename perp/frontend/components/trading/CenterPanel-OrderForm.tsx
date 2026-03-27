'use client';

import { useState, useCallback, useMemo } from 'react';
import { useWallet } from '@mysten/dapp-kit';
import { usePerpetualTrading } from '@/hooks/usePerpetualTrading';
import { calculateLiquidationPrice, calculatePositionSize, calculateRequiredMargin } from '@/lib/contractHelpers';
import { formatNumber, formatLeverage, getPnLColorClass } from '@/lib/formatters';
import { MOCK_PAIRS, MIN_LEVERAGE, MAX_LEVERAGE } from '@/lib/constants';
import LeverageSlider from './LeverageSlider';
import PairSelector from './PairSelector';
import DirectionToggle from './DirectionToggle';

interface CenterPanelOrderFormProps {
  selectedPair: string;
  onPairChange: (pair: string) => void;
  currentPrice: number;
  onTradeExecuted?: () => void;
}

export default function CenterPanelOrderForm({
  selectedPair,
  onPairChange,
  currentPrice,
  onTradeExecuted,
}: CenterPanelOrderFormProps) {
  const { connected } = useWallet();
  const { openPositionDirect, isLoading: isTxLoading, error: txError } = usePerpetualTrading();

  // Form state
  const [isLong, setIsLong] = useState(true);
  const [marginAmount, setMarginAmount] = useState(1000);
  const [leverage, setLeverage] = useState(10);
  const [useHiddenOrder, setUseHiddenOrder] = useState(false);
  const [marginMode, setMarginMode] = useState<'ISOLATED' | 'CROSS'>('ISOLATED');
  const [stopLoss, setStopLoss] = useState<number | null>(null);
  const [takeProfit, setTakeProfit] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isExecuting, setIsExecuting] = useState(false);

  // Calculations
  const calculations = useMemo(() => {
    const positionSize = calculatePositionSize(
      BigInt(Math.floor(marginAmount * 1e6)),
      BigInt(Math.floor(currentPrice * 1e10)),
      leverage
    );

    const requiredMargin = calculateRequiredMargin(
      positionSize,
      BigInt(Math.floor(currentPrice * 1e10)),
      leverage
    );

    const liquidationPrice = calculateLiquidationPrice(
      BigInt(Math.floor(currentPrice * 1e10)),
      isLong,
      BigInt(Math.floor(marginAmount * 1e6)),
      leverage
    );

    const openingFeePercent = 0.1; // 0.1%
    const openingFee = (marginAmount * leverage * currentPrice * openingFeePercent) / 100;

    return {
      positionSize: Number(positionSize) / 1e6,
      requiredMargin: Number(requiredMargin) / 1e6,
      liquidationPrice: Number(liquidationPrice) / 1e10,
      openingFee,
      exposureUSD: marginAmount * leverage,
    };
  }, [marginAmount, leverage, currentPrice, isLong]);

  const handleExecuteTrade = useCallback(async () => {
    if (!connected) {
      setError('Please connect wallet first');
      return;
    }

    if (marginAmount <= 0) {
      setError('Margin amount must be greater than 0');
      return;
    }

    if (leverage < MIN_LEVERAGE || leverage > MAX_LEVERAGE) {
      setError(`Leverage must be between ${MIN_LEVERAGE}x and ${MAX_LEVERAGE}x`);
      return;
    }

    setIsExecuting(true);
    setError(null);

    try {
      console.log('[v0] Executing trade:', {
        pair: selectedPair,
        isLong,
        margin: marginAmount,
        leverage,
        marginMode,
      });

      const result = await openPositionDirect({
        pairId: selectedPair,
        margin: BigInt(Math.floor(marginAmount * 1e6)),
        leverage: leverage,
        isLong: isLong,
        marginMode: marginMode,
        stopLoss: stopLoss ? BigInt(Math.floor(stopLoss * 1e10)) : undefined,
        takeProfit: takeProfit ? BigInt(Math.floor(takeProfit * 1e10)) : undefined,
      });

      if (result.success) {
        // Reset form
        setMarginAmount(1000);
        setLeverage(10);
        setError(null);
        setStopLoss(null);
        setTakeProfit(null);
        onTradeExecuted?.();
      } else {
        setError(result.error || 'Failed to execute trade');
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      setError(errorMsg);
      console.error('[v0] Trade execution error:', errorMsg);
    } finally {
      setIsExecuting(false);
    }
  }, [
    connected,
    marginAmount,
    leverage,
    selectedPair,
    isLong,
    marginMode,
    stopLoss,
    takeProfit,
    openPositionDirect,
    onTradeExecuted,
  ]);

  return (
    <div className="space-y-4 overflow-y-auto max-h-full">
      {/* Pair Selector */}
      <div>
        <label className="text-xs text-muted-foreground font-semibold block mb-2">Pair</label>
        <PairSelector
          selectedPair={selectedPair}
          onPairChange={onPairChange}
          pairs={Object.keys(MOCK_PAIRS)}
        />
      </div>

      {/* Direction Toggle */}
      <div>
        <label className="text-xs text-muted-foreground font-semibold block mb-2">Direction</label>
        <DirectionToggle isLong={isLong} onToggle={setIsLong} />
      </div>

      {/* Margin Mode Selector */}
      <div>
        <label className="text-xs text-muted-foreground font-semibold block mb-2">Margin Mode</label>
        <div className="grid grid-cols-2 gap-2">
          {(['ISOLATED', 'CROSS'] as const).map((mode) => (
            <button
              key={mode}
              onClick={() => setMarginMode(mode)}
              className={`py-2 rounded text-xs font-medium transition-colors ${
                marginMode === mode
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-black/30 text-muted-foreground hover:text-foreground'
              }`}
            >
              {mode}
            </button>
          ))}
        </div>
      </div>

      {/* Margin Amount Input */}
      <div>
        <label className="text-xs text-muted-foreground font-semibold block mb-2">
          Margin (USDC)
        </label>
        <input
          type="number"
          value={marginAmount}
          onChange={(e) => setMarginAmount(Math.max(0, parseFloat(e.target.value) || 0))}
          disabled={isExecuting}
          className="trading-input text-sm"
          placeholder="Enter margin amount"
          min="10"
          step="10"
        />
        <div className="text-xs text-muted-foreground mt-1">
          Available: $50,000 USDC
        </div>
      </div>

      {/* Leverage Slider */}
      <div>
        <label className="text-xs text-muted-foreground font-semibold block mb-2">
          Leverage: {formatLeverage(leverage)}
        </label>
        <LeverageSlider
          value={leverage}
          onChange={setLeverage}
          min={MIN_LEVERAGE}
          max={MAX_LEVERAGE}
          disabled={isExecuting}
        />
        <div className="text-xs text-muted-foreground mt-1">
          Position Size: {calculations.positionSize.toFixed(4)} {selectedPair.split('/')[0]}
        </div>
      </div>

      {/* Risk Indicators */}
      <div className="bg-black/30 rounded p-3 space-y-2 border border-border/50">
        <div className="text-xs text-muted-foreground">Risk Information</div>
        <div className="grid grid-cols-2 gap-2 text-xs">
          <div>
            <div className="text-muted-foreground">Exposure (USD)</div>
            <div className="font-mono font-semibold">${formatNumber(calculations.exposureUSD, 0)}</div>
          </div>
          <div>
            <div className="text-muted-foreground">Opening Fee</div>
            <div className="font-mono font-semibold text-orange-500">-${formatNumber(calculations.openingFee, 2)}</div>
          </div>
          <div className="col-span-2">
            <div className="text-muted-foreground">Liquidation Price</div>
            <div className={`font-mono font-bold ${getPnLColorClass(calculations.liquidationPrice - currentPrice)}`}>
              ${formatNumber(calculations.liquidationPrice, 2)}
            </div>
          </div>
        </div>
      </div>

      {/* Hidden Order Toggle */}
      <div className="border border-border rounded p-3 flex items-start gap-3">
        <input
          type="checkbox"
          id="hidden-order"
          checked={useHiddenOrder}
          onChange={(e) => setUseHiddenOrder(e.target.checked)}
          className="mt-1"
        />
        <label htmlFor="hidden-order" className="cursor-pointer">
          <div className="text-xs font-semibold text-foreground">Hidden Order</div>
          <div className="text-xs text-muted-foreground mt-1">
            Invisible orders. Visible advantage.
          </div>
        </label>
      </div>

      {/* Advanced Options - TP/SL (Collapsed by default) */}
      <details className="group">
        <summary className="text-xs text-muted-foreground font-semibold cursor-pointer hover:text-foreground transition-colors">
          TP/SL (Optional)
        </summary>
        <div className="space-y-2 mt-3">
          <input
            type="number"
            value={takeProfit || ''}
            onChange={(e) => setTakeProfit(e.target.value ? parseFloat(e.target.value) : null)}
            placeholder="Take Profit Price"
            className="trading-input text-xs"
          />
          <input
            type="number"
            value={stopLoss || ''}
            onChange={(e) => setStopLoss(e.target.value ? parseFloat(e.target.value) : null)}
            placeholder="Stop Loss Price"
            className="trading-input text-xs"
          />
        </div>
      </details>

      {/* Error Message */}
      {(error || txError) && (
        <div className="bg-red-500/10 border border-red-500/30 rounded p-2 text-xs text-red-500">
          {error || txError}
        </div>
      )}

      {/* Primary Action Button */}
      <button
        onClick={handleExecuteTrade}
        disabled={!connected || isExecuting || isTxLoading}
        className={`btn-primary-cta ${isLong ? 'bg-green-600 hover:bg-green-700' : 'bg-red-600 hover:bg-red-700'}`}
      >
        {isExecuting || isTxLoading ? (
          <span className="flex items-center justify-center gap-2">
            <span className="animate-spin">⌛</span>
            Executing...
          </span>
        ) : (
          `${isLong ? 'LONG' : 'SHORT'} ${selectedPair.split('/')[0]}`
        )}
      </button>

      {/* Disclaimer */}
      <div className="text-xs text-muted-foreground text-center py-2 border-t border-border pt-3">
        Trading involves high risk. Always use stop losses.
      </div>
    </div>
  );
}
