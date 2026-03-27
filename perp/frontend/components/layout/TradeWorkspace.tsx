'use client';

import { useState, useCallback } from 'react';
import { useWallet } from '@mysten/dapp-kit';
import SideNavigation from './SideNavigation';
import LeftPanelPriceChart from '../trading/LeftPanel-PriceChart';
import CenterPanelOrderForm from '../trading/CenterPanel-OrderForm';
import RightPanelOrderBook from '../trading/RightPanel-OrderBook';

export default function TradeWorkspace() {
  const { connected } = useWallet();
  const [selectedPair, setSelectedPair] = useState('BTC/USD');
  const [currentPrice, setCurrentPrice] = useState(45230.5);
  const [refreshTrigger, setRefreshTrigger] = useState(0);

  const handleTradeExecuted = useCallback(() => {
    // Trigger refresh in sidebar
    setRefreshTrigger((prev) => prev + 1);
  }, []);

  if (!connected) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center space-y-4">
          <h2 className="text-3xl font-bold">Welcome to OPerpetualDex</h2>
          <p className="text-muted-foreground text-lg">
            Connect your wallet to start trading perpetual futures
          </p>
          <div className="pt-4">
            <p className="text-sm text-muted-foreground">Use the Connect Wallet button in the header</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-[calc(100vh-140px)]">
      {/* Side Navigation - Portfolio & Positions */}
      <div className="w-64 border-r border-border overflow-y-auto">
        <SideNavigation refreshTrigger={refreshTrigger} />
      </div>

      {/* Main Trading Workspace - 3 Panels */}
      <div className="flex-1 p-4 overflow-hidden">
        <div className="h-full grid grid-cols-12 gap-4">
          {/* Left Panel - Price Chart (40%) */}
          <div className="col-span-5 border border-border rounded-lg bg-black/20 overflow-hidden flex flex-col">
            <LeftPanelPriceChart
              selectedPair={selectedPair}
              currentPrice={currentPrice}
              onPriceUpdate={setCurrentPrice}
            />
          </div>

          {/* Center Panel - Order Entry Form (30%) */}
          <div className="col-span-3 border border-border rounded-lg bg-black/20 p-4 overflow-y-auto">
            <CenterPanelOrderForm
              selectedPair={selectedPair}
              onPairChange={setSelectedPair}
              currentPrice={currentPrice}
              onTradeExecuted={handleTradeExecuted}
            />
          </div>

          {/* Right Panel - Order Book (30%) */}
          <div className="col-span-4 border border-border rounded-lg bg-black/20 overflow-hidden flex flex-col">
            <RightPanelOrderBook selectedPair={selectedPair} />
          </div>
        </div>
      </div>
    </div>
  );
}
