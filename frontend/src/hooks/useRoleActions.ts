import { useCurrentAccount, useSuiClient } from '@mysten/dapp-kit';
import { useCallback } from 'react';

// Your deployed contract IDs
const GAME_PACKAGE_ID = '0x18a05df19f0a609ff47c6cc4fbddc558bb9097e7a757b769d412659b696bb879';

// Role constants (from role_machine.move)
const ROLE_CITIZEN = 1;
const ROLE_SABOTEUR = 2;

export interface RoleDistribution {
  citizen_count: number;
  saboteur_count: number;
}

export function useRoleActions() {
  const client = useSuiClient();
  const currentAccount = useCurrentAccount();

  // Get role name from role number
  const getRoleName = useCallback((role: number): string => {
    switch (role) {
      case ROLE_CITIZEN:
        return 'Citizen';
      case ROLE_SABOTEUR:
        return 'Saboteur';
      default:
        return 'Unknown';
    }
  }, []);

  // Get role description
  const getRoleDescription = useCallback((role: number): string => {
    switch (role) {
      case ROLE_CITIZEN:
        return 'Work together to eliminate saboteurs and reach consensus';
      case ROLE_SABOTEUR:
        return 'Disrupt consensus and survive until the end';
      default:
        return 'Unknown role';
    }
  }, []);

  // Get role color for UI styling
  const getRoleColor = useCallback((role: number): string => {
    switch (role) {
      case ROLE_CITIZEN:
        return '#3B82F6'; // Blue
      case ROLE_SABOTEUR:
        return '#EF4444'; // Red
      default:
        return '#6B7280'; // Gray
    }
  }, []);

  // Check if a player has revealed their role
  const hasRevealedRole = useCallback(async (
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
        const roleMachine = fields.role_machine?.fields;

        if (roleMachine?.role_revealed?.fields?.contents) {
          const revealedEntries = roleMachine.role_revealed.fields.contents;
          const playerEntry = revealedEntries.find((entry: any) =>
            entry.fields?.key === playerAddress
          );

          return playerEntry?.fields?.value === true;
        }
      }

      return false;
    } catch (error) {
      console.error('Failed to check role reveal status:', error);
      return false;
    }
  }, [client]);

  // Get role distribution for a game
  const getRoleDistribution = useCallback(async (
    gameId: string
  ): Promise<RoleDistribution | null> => {
    try {
      const gameObject = await client.getObject({
        id: gameId,
        options: {
          showContent: true,
        },
      });

      if (gameObject.data?.content && 'fields' in gameObject.data.content) {
        const fields = gameObject.data.content.fields as any;
        const roleMachine = fields.role_machine?.fields;

        if (roleMachine) {
          return {
            citizen_count: parseInt(roleMachine.citizen_count || '0'),
            saboteur_count: parseInt(roleMachine.saboteur_count || '0'),
          };
        }
      }

      return null;
    } catch (error) {
      console.error('Failed to get role distribution:', error);
      return null;
    }
  }, [client]);

  // Calculate expected saboteur count based on player count
  const calculateExpectedSaboteurs = useCallback((playerCount: number): number => {
    if (playerCount < 3) return 0;
    // 1 saboteur per 3 players
    return Math.floor(playerCount / 3);
  }, []);

  // Calculate consensus threshold (50% of alive players)
  const calculateConsensusThreshold = useCallback((aliveCount: number): number => {
    return Math.ceil((aliveCount * 50) / 100);
  }, []);

  // Check if consensus was reached
  const checkConsensus = useCallback((
    aliveCount: number,
    option1Votes: number,
    option2Votes: number,
    option3Votes: number
  ): { reached: boolean; threshold: number; maxVotes: number } => {
    const threshold = calculateConsensusThreshold(aliveCount);
    const maxVotes = Math.max(option1Votes, option2Votes, option3Votes);
    const reached = maxVotes >= threshold;

    return {
      reached,
      threshold,
      maxVotes,
    };
  }, [calculateConsensusThreshold]);

  // Determine winning option (or null if no consensus)
  const getWinningOption = useCallback((
    aliveCount: number,
    option1Votes: number,
    option2Votes: number,
    option3Votes: number
  ): number | null => {
    const { reached, maxVotes } = checkConsensus(
      aliveCount,
      option1Votes,
      option2Votes,
      option3Votes
    );

    if (!reached) return null;

    if (option1Votes === maxVotes) return 1;
    if (option2Votes === maxVotes) return 2;
    if (option3Votes === maxVotes) return 3;

    return null;
  }, [checkConsensus]);

  // Get saboteur win conditions explanation
  const getSaboteurWinConditions = useCallback((): string[] => {
    return [
      'Control ≥50% of survivors',
      'Prevent consensus for 2+ consecutive rounds',
      'Survive until max rounds reached',
    ];
  }, []);

  // Get citizen win conditions explanation
  const getCitizenWinConditions = useCallback((): string[] => {
    return [
      'Eliminate all saboteurs',
      'Maintain consensus and cooperation',
    ];
  }, []);

  return {
    getRoleName,
    getRoleDescription,
    getRoleColor,
    hasRevealedRole,
    getRoleDistribution,
    calculateExpectedSaboteurs,
    calculateConsensusThreshold,
    checkConsensus,
    getWinningOption,
    getSaboteurWinConditions,
    getCitizenWinConditions,
    // Constants
    ROLE_CITIZEN,
    ROLE_SABOTEUR,
    CONSENSUS_THRESHOLD_PERCENT: 50,
  };
}
