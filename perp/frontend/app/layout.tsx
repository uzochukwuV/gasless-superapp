import type { Metadata, Viewport } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import { ConnectButton, WalletProvider } from '@mysten/dapp-kit';
import '@mysten/dapp-kit/styles.css';
import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: 'OPerpetualDex - Decentralized Perpetual Futures',
  description: 'Trade perpetual futures on Sui Network with advanced risk management and real-time market data.',
  keywords: [
    'perpetual futures',
    'DEX',
    'trading',
    'Sui',
    'cryptocurrency',
    'leverage trading',
  ],
  authors: [{ name: 'OPerpetualDex' }],
  openGraph: {
    title: 'OPerpetualDex',
    description: 'Decentralized Perpetual Futures Trading on Sui',
    type: 'website',
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  themeColor: '#000000',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body
        className={`${geistSans.variable} ${geistMono.variable} bg-background text-foreground antialiased`}
      >
        <WalletProvider>
          <div className="min-h-screen flex flex-col">
            {/* Header */}
            <header className="border-b border-border bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
              <div className="max-w-full px-4 py-4 flex justify-between items-center">
                <div className="flex items-center gap-2">
                  <h1 className="text-2xl font-bold">OPerpetualDex</h1>
                </div>
                <ConnectButton />
              </div>
            </header>

            {/* Main Content */}
            <main className="flex-1 w-full">{children}</main>

            {/* Footer */}
            <footer className="border-t border-border bg-background/50 py-4 px-4">
              <div className="text-center text-sm text-muted-foreground">
                © 2026 OPerpetualDex. Trading on Sui Network.
              </div>
            </footer>
          </div>
        </WalletProvider>
      </body>
    </html>
  );
}
