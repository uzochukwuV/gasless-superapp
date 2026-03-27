import { NextRequest, NextResponse } from 'next/server';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { fromBase64 } from '@mysten/sui/utils';
import { getSuiClient } from '@/lib/suiClient';
import { TOKEN_SYMBOL } from '@/lib/constants';

/**
 * Gas Sponsorship API Route
 *
 * This endpoint receives an unsigned transaction from the frontend,
 * signs it with the sponsor wallet, and returns the signed transaction
 * bytes for the user to submit to the network.
 *
 * Flow:
 * 1. Frontend builds transaction
 * 2. Frontend sends transaction bytes to this endpoint
 * 3. Backend signs with sponsor wallet
 * 4. Frontend submits signed transaction
 */

// Sponsor wallet keypair (loaded from environment variable)
function getSponsorKeypair(): Ed25519Keypair {
  const privateKey = process.env.SPONSOR_PRIVATE_KEY;

  if (!privateKey) {
    throw new Error('SPONSOR_PRIVATE_KEY environment variable not set');
  }

  try {
    // Support both Bech32 (suiprivkey1...) and base64 formats
    if (privateKey.startsWith('suiprivkey')) {
      // Bech32 format - use the fromSecretKey method with the key directly
      return Ed25519Keypair.fromSecretKey(privateKey);
    } else {
      // Base64 format
      const privateKeyBytes = fromBase64(privateKey);
      return Ed25519Keypair.fromSecretKey(privateKeyBytes);
    }
  } catch (error) {
    throw new Error('Invalid SPONSOR_PRIVATE_KEY format. Must be Bech32 (suiprivkey1...) or base64 encoded.');
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { transactionKindBytes, sender } = body;

    // Validate request
    if (!transactionKindBytes || !sender) {
      return NextResponse.json(
        { error: 'Missing transactionKindBytes or sender address' },
        { status: 400 }
      );
    }

    // Get sponsor keypair
    const sponsorKeypair = getSponsorKeypair();
    const sponsorAddress = sponsorKeypair.getPublicKey().toSuiAddress();

    console.log('Gas Sponsorship Request:', {
      sender,
      sponsor: sponsorAddress,
      timestamp: new Date().toISOString(),
    });

    // Initialize Sui client
    const client = getSuiClient();

    // STEP 1: Deserialize transaction KIND (not full transaction)
    // Transaction.fromKind() creates a transaction from just the command bytes
    const txKindBytesArray = new Uint8Array(transactionKindBytes);
    const tx = Transaction.fromKind(txKindBytesArray);

    // STEP 2: Set the sender and gas owner (sponsor)
    tx.setSender(sender);
    tx.setGasOwner(sponsorAddress);

    // STEP 3: Get sponsor's coins for gas payment
    const sponsorCoins = await client.getAllCoins({
      owner: sponsorAddress,
    });

    if (sponsorCoins.data.length === 0) {
      throw new Error('Sponsor has no coins for gas');
    }

    // Use the first coin as gas payment
    const gasCoin = sponsorCoins.data[0];
    tx.setGasPayment([
      {
        objectId: gasCoin.coinObjectId,
        version: gasCoin.version,
        digest: gasCoin.digest,
      },
    ]);

    // STEP 4: Set gas budget (50 million MIST = 0.05 OCT)
    tx.setGasBudget(50_000_000);

    // STEP 5: Build and SIGN the transaction with sponsor keypair
    const builtTxBytes = await tx.build({ client });
    const sponsorSignature = await sponsorKeypair.signTransaction(builtTxBytes);

    console.log('Transaction sponsored and signed by:', sponsorAddress);

    // STEP 6: Return the sponsored transaction bytes AND sponsor signature
    // Frontend will also sign this same transaction, then execute with both signatures
    return NextResponse.json({
      success: true,
      sponsoredTransaction: {
        bytes: sponsorSignature.bytes, // Already a base64 string from signTransaction
        signature: sponsorSignature.signature,
        sponsor: sponsorAddress,
      },
    });

  } catch (error) {
    console.error('Gas sponsorship error:', error);

    return NextResponse.json(
      {
        error: 'Failed to sponsor transaction',
        details: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    );
  }
}

// Health check endpoint
export async function GET() {
  try {
    const sponsorKeypair = getSponsorKeypair();
    const sponsorAddress = sponsorKeypair.getPublicKey().toSuiAddress();

    // Check sponsor balance
    const client = getSuiClient();
    const balance = await client.getBalance({
      owner: sponsorAddress,
    });

    return NextResponse.json({
      status: 'operational',
      sponsor: sponsorAddress,
      balance: {
        total: balance.totalBalance,
        formatted: `${Number(balance.totalBalance) / 1_000_000_000} ${TOKEN_SYMBOL}`,
      },
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    return NextResponse.json(
      {
        status: 'error',
        error: error instanceof Error ? error.message : 'Unknown error'
      },
      { status: 500 }
    );
  }
}
