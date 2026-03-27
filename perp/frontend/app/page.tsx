'use client';

import { Suspense } from 'react';
import dynamic from 'next/dynamic';

// Dynamically import the trading workspace to avoid SSR issues
const TradeWorkspace = dynamic(() => import('@/components/layout/TradeWorkspace'), {
  ssr: false,
  loading: () => <LoadingScreen />,
});

function LoadingScreen() {
  return (
    <div className="flex items-center justify-center h-screen">
      <div className="text-center">
        <div className="mb-4 text-2xl font-bold">Loading OPerpetualDex...</div>
        <div className="animate-pulse">
          <div className="h-2 bg-gradient-to-r from-primary/50 to-transparent rounded-full"></div>
        </div>
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <Suspense fallback={<LoadingScreen />}>
      <TradeWorkspace />
    </Suspense>
  );
}
