// Sui blockchain client configuration
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { NETWORK } from './constants';

/**
 * Get Sui network URL based on environment
 */
export function getSuiNetworkUrl(): string {
  switch (NETWORK) {
    case 'mainnet':
      return getFullnodeUrl('mainnet');
    case 'testnet':
      return getFullnodeUrl('testnet');
    case 'devnet':
      return getFullnodeUrl('devnet');
    default:
      return getFullnodeUrl('testnet');
  }
}

/**
 * Singleton Sui client instance
 */
let suiClient: SuiClient | null = null;

/**
 * Get or create Sui client
 */
export function getSuiClient(): SuiClient {
  if (!suiClient) {
    suiClient = new SuiClient({
      url: getSuiNetworkUrl(),
    });
  }
  return suiClient;
}

/**
 * Fetch object data from Sui blockchain
 */
export async function getObjectData(objectId: string) {
  const client = getSuiClient();
  try {
    const data = await client.getObject({
      id: objectId,
      options: {
        showType: true,
        showContent: true,
        showOwner: true,
        showPreviousTransaction: true,
      },
    });
    return data;
  } catch (error) {
    console.error('[v0] Error fetching object:', error);
    return null;
  }
}

/**
 * Fetch owned objects for an address
 */
export async function getOwnedObjects(address: string, type?: string) {
  const client = getSuiClient();
  try {
    const objects = await client.getOwnedObjects({
      owner: address,
      filter: type ? { StructType: type } : undefined,
      options: {
        showType: true,
        showContent: true,
      },
    });
    return objects;
  } catch (error) {
    console.error('[v0] Error fetching owned objects:', error);
    return null;
  }
}

/**
 * Listen to object changes
 */
export function subscribeToObject(objectId: string, callback: (data: any) => void) {
  const client = getSuiClient();
  const subscriptionId = client.subscribeEvent({
    filter: {
      MoveModule: {
        package: objectId,
      },
    },
    onMessage: (event) => {
      callback(event);
    },
  });
  return subscriptionId;
}

/**
 * Get transaction status
 */
export async function getTransactionStatus(digest: string) {
  const client = getSuiClient();
  try {
    const tx = await client.getTransactionBlock({
      digest,
      options: {
        showInput: true,
        showRawInput: true,
        showEffects: true,
        showEvents: true,
      },
    });
    return tx;
  } catch (error) {
    console.error('[v0] Error fetching transaction:', error);
    return null;
  }
}

/**
 * Wait for transaction confirmation
 */
export async function waitForTransaction(
  digest: string,
  maxAttempts: number = 30,
  intervalMs: number = 2000
): Promise<boolean> {
  for (let i = 0; i < maxAttempts; i++) {
    const tx = await getTransactionStatus(digest);
    if (tx?.effects?.status.status === 'success') {
      return true;
    }
    if (tx?.effects?.status.status === 'failure') {
      return false;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return false;
}

/**
 * Estimate gas for transaction (simulate)
 */
export async function estimateGas(tx: any): Promise<bigint> {
  const client = getSuiClient();
  try {
    // This is a simplified estimation
    // Real implementation would use dryRunTransactionBlock
    return BigInt(1000000); // 0.001 SUI
  } catch (error) {
    console.error('[v0] Error estimating gas:', error);
    return BigInt(1000000);
  }
}
