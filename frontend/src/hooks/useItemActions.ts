import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { useCallback } from 'react';

// Your deployed contract IDs
const GAME_PACKAGE_ID = '0x18a05df19f0a609ff47c6cc4fbddc558bb9097e7a757b769d412659b696bb879';
const ITEM_SHOP_ID = '0x7581b5762c79b821df47482bef07a3c7f3cc08f101c804fcfcb1271d88621856';
const CLOCK_OBJECT = '0x6';

// Item pricing (from items.move)
const BASE_IMMUNITY_PRICE = 100_000_000; // 0.1 OCT in MIST
const PRICE_INCREASE_PER_TIER = 50_000_000; // 0.05 OCT per tier

export interface ImmunityTokenData {
  id: string;
  tier: number;
  purchaseTime: number;
}

export function useItemActions() {
  const client = useSuiClient();
  const currentAccount = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();

  // Helper: Get Item Shop ID
  const getItemShop = useCallback((): string => {
    return ITEM_SHOP_ID;
  }, []);

  // Calculate immunity token price for a specific tier
  const calculateImmunityPrice = useCallback((tier: number): number => {
    return BASE_IMMUNITY_PRICE + ((tier - 1) * PRICE_INCREASE_PER_TIER);
  }, []);

  // Buy an immunity token
  const buyImmunityToken = useCallback(async (
    tier: number,
    paymentCoinId: string
  ) => {
    if (!currentAccount) throw new Error('No account connected');

    const tx = new Transaction();
    const shopId = getItemShop();

    tx.moveCall({
      target: `${GAME_PACKAGE_ID}::items::buy_immunity_token`,
      arguments: [
        tx.object(shopId),
        tx.pure.u8(tier),
        tx.object(paymentCoinId),
        tx.object(CLOCK_OBJECT),
      ],
    });

    return new Promise((resolve, reject) => {
      signAndExecute(
        { transaction: tx },
        {
          onSuccess: (result) => {
            console.log('Immunity token purchased:', result);
            resolve(result);
          },
          onError: (error) => {
            console.error('Failed to purchase immunity token:', error);
            reject(error);
          },
        }
      );
    });
  }, [currentAccount, signAndExecute, getItemShop]);

  // Use immunity token in a game (called from useGameActions)
  const useImmunityToken = useCallback(async (
    gameId: string,
    tokenId: string
  ) => {
    if (!currentAccount) throw new Error('No account connected');

    const tx = new Transaction();

    tx.moveCall({
      target: `${GAME_PACKAGE_ID}::battle_royale::use_immunity_token`,
      arguments: [
        tx.object(gameId),
        tx.object(tokenId),
      ],
    });

    return new Promise((resolve, reject) => {
      signAndExecute(
        { transaction: tx },
        {
          onSuccess: (result) => {
            console.log('Immunity token used:', result);
            resolve(result);
          },
          onError: (error) => {
            console.error('Failed to use immunity token:', error);
            reject(error);
          },
        }
      );
    });
  }, [currentAccount, signAndExecute]);

  // Get immunity tokens owned by current user
  const getMyImmunityTokens = useCallback(async (): Promise<ImmunityTokenData[]> => {
    if (!currentAccount?.address) {
      return [];
    }

    try {
      const objects = await client.getOwnedObjects({
        owner: currentAccount.address,
        filter: {
          StructType: `${GAME_PACKAGE_ID}::items::ImmunityToken`,
        },
        options: {
          showContent: true,
        },
      });

      return objects.data
        .filter((obj) => obj.data?.content && 'fields' in obj.data.content)
        .map((obj) => {
          const content = obj.data!.content as any;
          const fields = content.fields;

          return {
            id: obj.data!.objectId,
            tier: parseInt(fields.tier || '1'),
            purchaseTime: parseInt(fields.purchase_time || '0'),
          };
        });
    } catch (error) {
      console.error('Failed to get immunity tokens:', error);
      return [];
    }
  }, [client, currentAccount]);

  // Get immunity tokens for a specific address
  const getImmunityTokens = useCallback(async (
    address: string
  ): Promise<ImmunityTokenData[]> => {
    try {
      const objects = await client.getOwnedObjects({
        owner: address,
        filter: {
          StructType: `${GAME_PACKAGE_ID}::items::ImmunityToken`,
        },
        options: {
          showContent: true,
        },
      });

      return objects.data
        .filter((obj) => obj.data?.content && 'fields' in obj.data.content)
        .map((obj) => {
          const content = obj.data!.content as any;
          const fields = content.fields;

          return {
            id: obj.data!.objectId,
            tier: parseInt(fields.tier || '1'),
            purchaseTime: parseInt(fields.purchase_time || '0'),
          };
        });
    } catch (error) {
      console.error('Failed to get immunity tokens:', error);
      return [];
    }
  }, [client]);

  // Check if player has used immunity in a game
  const hasUsedImmunity = useCallback(async (
    gameId: string,
    playerAddress: string
  ): Promise<boolean> => {
    try {
      const gameObject = await client.getObject({
        id: gameId,
        options: {
          showContent: true,
        },
      });

      if (gameObject.data?.content && 'fields' in gameObject.data.content) {
        const fields = gameObject.data.content.fields as any;
        const immunityUsed = fields.immunity_used?.fields?.contents || [];

        return immunityUsed.some((entry: any) =>
          entry.fields?.key === playerAddress && entry.fields?.value === true
        );
      }

      return false;
    } catch (error) {
      console.error('Failed to check immunity usage:', error);
      return false;
    }
  }, [client]);

  // Get total sales count from item shop
  const getTotalSales = useCallback(async (): Promise<number> => {
    try {
      const shopId = getItemShop();
      const shopObject = await client.getObject({
        id: shopId,
        options: {
          showContent: true,
        },
      });

      if (shopObject.data?.content && 'fields' in shopObject.data.content) {
        const fields = shopObject.data.content.fields as any;
        return parseInt(fields.total_sales || '0');
      }

      return 0;
    } catch (error) {
      console.error('Failed to get total sales:', error);
      return 0;
    }
  }, [client, getItemShop]);

  // Format price in OCT (convert from MIST)
  const formatPrice = useCallback((priceInMist: number): string => {
    const priceInOct = priceInMist / 1_000_000_000;
    return `${priceInOct.toFixed(2)} OCT`;
  }, []);

  // Get price breakdown for all tiers
  const getPricingTable = useCallback((): Array<{ tier: number; price: number; priceOct: string }> => {
    return [1, 2, 3, 4, 5].map((tier) => {
      const price = calculateImmunityPrice(tier);
      return {
        tier,
        price,
        priceOct: formatPrice(price),
      };
    });
  }, [calculateImmunityPrice, formatPrice]);

  return {
    buyImmunityToken,
    useImmunityToken,
    getMyImmunityTokens,
    getImmunityTokens,
    hasUsedImmunity,
    getTotalSales,
    calculateImmunityPrice,
    formatPrice,
    getPricingTable,
    getItemShop,
    // Constants
    BASE_IMMUNITY_PRICE,
    PRICE_INCREASE_PER_TIER,
  };
}
