import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from '@mysten/dapp-kit';
import { Transaction } from '@mysten/sui/transactions';
import { useCallback } from 'react';

// Your deployed contract IDs
const GAME_PACKAGE_ID = '0x18a05df19f0a609ff47c6cc4fbddc558bb9097e7a757b769d412659b696bb879';
const BADGE_REGISTRY_ID = '0x7824cb0f993210206d0eaf4c8b1ef1cfa2f6532275b3172e9aaeade314e9d43d';

// Reputation level constants (from reputation.move)
const LEVEL_BRONZE = 1;
const LEVEL_SILVER = 2;
const LEVEL_GOLD = 3;
const LEVEL_PLATINUM = 4;
const LEVEL_DIAMOND = 5;

export interface BadgeStats {
  games_played: number;
  games_won: number;
  points: number;
  level: number;
}

export function useReputationActions() {
  const client = useSuiClient();
  const currentAccount = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();

  // Helper: Get Badge Registry ID
  const getBadgeRegistry = useCallback((): string => {
    return BADGE_REGISTRY_ID;
  }, []);

  // Mint a new reputation badge for a player (called automatically by the game)
  const mintBadge = useCallback(async (playerAddress: string) => {
    if (!currentAccount) throw new Error('No account connected');

    const tx = new Transaction();
    const badgeRegistryId = getBadgeRegistry();

    tx.moveCall({
      target: `${GAME_PACKAGE_ID}::reputation::mint_badge`,
      arguments: [
        tx.object(badgeRegistryId),
        tx.pure.address(playerAddress),
      ],
    });

    return new Promise((resolve, reject) => {
      signAndExecute(
        { transaction: tx },
        {
          onSuccess: (result) => {
            console.log('Badge minted:', result);
            resolve(result);
          },
          onError: (error) => {
            console.error('Failed to mint badge:', error);
            reject(error);
          },
        }
      );
    });
  }, [currentAccount, signAndExecute, getBadgeRegistry]);

  // Update badge after game completion (called automatically by finalize_round)
  const updateBadge = useCallback(async (
    badgeRegistryId: string,
    playerAddress: string,
    won: boolean
  ) => {
    if (!currentAccount) throw new Error('No account connected');

    const tx = new Transaction();

    tx.moveCall({
      target: `${GAME_PACKAGE_ID}::reputation::update_badge`,
      arguments: [
        tx.object(badgeRegistryId),
        tx.pure.address(playerAddress),
        tx.pure.bool(won),
      ],
    });

    return new Promise((resolve, reject) => {
      signAndExecute(
        { transaction: tx },
        {
          onSuccess: (result) => {
            console.log('Badge updated:', result);
            resolve(result);
          },
          onError: (error) => {
            console.error('Failed to update badge:', error);
            reject(error);
          },
        }
      );
    });
  }, [currentAccount, signAndExecute]);

  // Query badge statistics for a player
  const getBadgeStats = useCallback(async (
    playerAddress: string
  ): Promise<BadgeStats | null> => {
    try {
      // Query for ReputationBadge objects owned by the player
      const objects = await client.getOwnedObjects({
        owner: playerAddress,
        filter: {
          StructType: `${GAME_PACKAGE_ID}::reputation::ReputationBadge`,
        },
        options: {
          showContent: true,
        },
      });

      if (objects.data.length === 0) {
        return null;
      }

      // Get the first badge (players should only have one)
      const badgeObject = objects.data[0];
      const content = badgeObject.data?.content;

      if (content && 'fields' in content) {
        const fields = content.fields as any;
        return {
          games_played: parseInt(fields.games_played || '0'),
          games_won: parseInt(fields.games_won || '0'),
          points: parseInt(fields.points || '0'),
          level: parseInt(fields.level || '1'),
        };
      }

      return null;
    } catch (error) {
      console.error('Failed to get badge stats:', error);
      return null;
    }
  }, [client]);

  // Check if a player has a reputation badge
  const hasBadge = useCallback(async (playerAddress: string): Promise<boolean> => {
    try {
      const badgeRegistryId = getBadgeRegistry();

      // Query the BadgeRegistry to check if player has a badge
      const registryObject = await client.getObject({
        id: badgeRegistryId,
        options: {
          showContent: true,
        },
      });

      if (registryObject.data?.content && 'fields' in registryObject.data.content) {
        const fields = registryObject.data.content.fields as any;
        const playerBadges = fields.player_badges?.fields?.contents || [];

        // Check if player address exists in the registry
        return playerBadges.some((entry: any) =>
          entry.fields?.key === playerAddress
        );
      }

      return false;
    } catch (error) {
      console.error('Failed to check badge existence:', error);
      return false;
    }
  }, [client, getBadgeRegistry]);

  // Get level name from level number
  const getLevelName = useCallback((level: number): string => {
    switch (level) {
      case LEVEL_BRONZE:
        return 'Bronze';
      case LEVEL_SILVER:
        return 'Silver';
      case LEVEL_GOLD:
        return 'Gold';
      case LEVEL_PLATINUM:
        return 'Platinum';
      case LEVEL_DIAMOND:
        return 'Diamond';
      default:
        return 'Unknown';
    }
  }, []);

  // Calculate win rate percentage
  const calculateWinRate = useCallback((stats: BadgeStats): number => {
    if (stats.games_played === 0) return 0;
    return (stats.games_won / stats.games_played) * 100;
  }, []);

  return {
    mintBadge,
    updateBadge,
    getBadgeStats,
    hasBadge,
    getLevelName,
    calculateWinRate,
    getBadgeRegistry,
    // Constants
    LEVEL_BRONZE,
    LEVEL_SILVER,
    LEVEL_GOLD,
    LEVEL_PLATINUM,
    LEVEL_DIAMOND,
  };
}
