'use client';

import { useState, useEffect } from 'react';
import { useWallet } from '@mysten/dapp-kit';
import { formatNumber, formatPercent, formatPnL } from '@/lib/formatters';
import PortfolioCard from '../portfolio/PortfolioCard';
import PositionsList from '../portfolio/PositionsList';
import TransactionHistory from '../portfolio/TransactionHistory';
import DepositMarginModal from '../modals/DepositMarginModal';
import WithdrawMarginModal from '../modals/WithdrawMarginModal';

interface SideNavigationProps {
  refreshTrigger?: number;
}

export default function SideNavigation({ refreshTrigger = 0 }: SideNavigationProps) {
  const { currentAccount } = useWallet();
  const [totalCollateral, setTotalCollateral] = useState(50000);
  const [totalPnL, setTotalPnL] = useState(2350.75);
  const [marginRatio, setMarginRatio] = useState(75.5);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isDepositOpen, setIsDepositOpen] = useState(false);
  const [isWithdrawOpen, setIsWithdrawOpen] = useState(false);

  useEffect(() => {
    // Simulate data refresh
    if (refreshTrigger > 0) {
      setIsRefreshing(true);
      setTimeout(() => setIsRefreshing(false), 500);
    }
  }, [refreshTrigger]);

  const pnlPercentage = (totalPnL / totalCollateral) * 100;
  const isHealthy = marginRatio > 10; // Healthy if > 10%
  const isAtRisk = marginRatio > 0 && marginRatio <= 10; // At risk if between 0-10%

  return (
    <div className="p-4 space-y-6">
      {/* User Info */}
      <div className="space-y-2 pb-4 border-b border-border">
        <div className="text-xs text-muted-foreground">ACCOUNT</div>
        <div className="text-xs font-mono text-foreground truncate">
          {currentAccount?.address ? `${currentAccount.address.slice(0, 6)}...${currentAccount.address.slice(-4)}` : 'Not connected'}
        </div>
      </div>

      {/* Portfolio Card */}
      <PortfolioCard
        totalCollateral={totalCollateral}
        totalPnL={totalPnL}
        marginRatio={marginRatio}
        isHealthy={isHealthy}
        isAtRisk={isAtRisk}
        isLoading={isRefreshing}
      />

      {/* Quick Stats */}
      <div className="space-y-3 text-sm">
        <div className="flex justify-between items-center">
          <span className="text-muted-foreground">P&L</span>
          <span className={totalPnL >= 0 ? 'text-green-500' : 'text-red-500'}>
            {totalPnL >= 0 ? '+' : ''}{formatNumber(totalPnL, 2)}
          </span>
        </div>
        <div className="flex justify-between items-center">
          <span className="text-muted-foreground">P&L %</span>
          <span className={pnlPercentage >= 0 ? 'text-green-500' : 'text-red-500'}>
            {pnlPercentage >= 0 ? '+' : ''}{formatPercent(pnlPercentage, 2)}
          </span>
        </div>
        <div className="flex justify-between items-center">
          <span className="text-muted-foreground">Margin Ratio</span>
          <span className={marginRatio > 50 ? 'text-green-500' : marginRatio > 10 ? 'text-yellow-500' : 'text-red-500'}>
            {formatPercent(marginRatio, 1, false)}
          </span>
        </div>
      </div>

      {/* Divider */}
      <div className="h-px bg-border"></div>

      {/* Positions List */}
      <div className="space-y-3">
        <div className="text-xs text-muted-foreground font-semibold">POSITIONS</div>
        <PositionsList isLoading={isRefreshing} />
      </div>

      {/* Action Buttons */}
      <div className="space-y-2 pt-4 border-t border-border">
        <button onClick={() => setIsDepositOpen(true)} className="w-full px-3 py-2 bg-green-500/10 text-green-500 border border-green-500/30 rounded text-sm font-medium hover:bg-green-500/20 transition-colors">
          Deposit
        </button>
        <button onClick={() => setIsWithdrawOpen(true)} className="w-full px-3 py-2 bg-blue-500/10 text-blue-500 border border-blue-500/30 rounded text-sm font-medium hover:bg-blue-500/20 transition-colors">
          Withdraw
        </button>
      </div>

      {/* Transaction History */}
      <div className="space-y-2 pt-4 border-t border-border">
        <div className="text-xs text-muted-foreground font-semibold">RECENT TRANSACTIONS</div>
        <TransactionHistory />
      </div>

      {/* Settings */}
      <div className="space-y-2 pt-4 border-t border-border">
        <button className="w-full text-left px-3 py-2 text-xs text-muted-foreground hover:text-foreground transition-colors">
          Settings
        </button>
        <button className="w-full text-left px-3 py-2 text-xs text-muted-foreground hover:text-foreground transition-colors">
          Transactions
        </button>
        <button className="w-full text-left px-3 py-2 text-xs text-muted-foreground hover:text-foreground transition-colors">
          Help
        </button>
      </div>

      {/* Modals */}
      <DepositMarginModal
        isOpen={isDepositOpen}
        onClose={() => setIsDepositOpen(false)}
        onSuccess={() => {
          setTotalCollateral((prev) => prev + 1000);
          setIsRefreshing(true);
          setTimeout(() => setIsRefreshing(false), 500);
        }}
      />
      <WithdrawMarginModal
        isOpen={isWithdrawOpen}
        onClose={() => setIsWithdrawOpen(false)}
        availableMargin={totalCollateral * 0.5}
        onSuccess={() => {
          setTotalCollateral((prev) => Math.max(0, prev - 1000));
          setIsRefreshing(true);
          setTimeout(() => setIsRefreshing(false), 500);
        }}
      />
    </div>
  );
}
