module game_onchain::reputation {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::event;
    use one::table::{Self, Table};

    // === Constants ===

    // Reputation levels based on win rate
    const LEVEL_BRONZE: u8 = 1;    // 0-20% win rate
    const LEVEL_SILVER: u8 = 2;    // 20-40% win rate
    const LEVEL_GOLD: u8 = 3;      // 40-60% win rate
    const LEVEL_PLATINUM: u8 = 4;  // 60-80% win rate
    const LEVEL_DIAMOND: u8 = 5;   // 80-100% win rate

    // === Error Codes ===
    const EBadgeNotFound: u64 = 300;
    const ENotBadgeOwner: u64 = 301;

    // === Structs ===

    /// Soul-Bound Token (SBT) for player reputation
    /// Note: NO 'store' ability = non-transferable!
    public struct ReputationBadge has key {
        id: UID,
        player: address,

        // Cumulative stats
        games_played: u64,
        games_won: u64,
        total_points: u64,

        // Role-specific wins
        citizen_wins: u64,
        saboteur_wins: u64,

        // Performance metrics
        perfect_consensus_rounds: u64,  // Rounds where player voted with majority
        times_eliminated: u64,

        // Computed level (1-5)
        level: u8,

        // Tracking
        last_updated: u64,
    }

    /// Global registry to track player badges
    public struct BadgeRegistry has key {
        id: UID,
        player_badges: Table<address, ID>,  // player -> badge ID
    }

    // === Events ===

    public struct BadgeRegistryCreated has copy, drop {
        registry_id: ID,
    }

    public struct BadgeMinted has copy, drop {
        badge_id: ID,
        player: address,
        initial_level: u8,
    }

    public struct BadgeUpdated has copy, drop {
        badge_id: ID,
        player: address,
        games_played: u64,
        games_won: u64,
        new_level: u8,
        total_points: u64,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let registry = BadgeRegistry {
            id: object::new(ctx),
            player_badges: table::new(ctx),
        };

        event::emit(BadgeRegistryCreated {
            registry_id: object::id(&registry),
        });

        transfer::share_object(registry);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Public Functions ===

    /// Mint new reputation badge for a player
    public fun mint_badge(
        registry: &mut BadgeRegistry,
        player: address,
        initial_points: u64,
        won: bool,
        role_was_citizen: bool,
        timestamp: u64,
        ctx: &mut TxContext
    ) {
        let games_won = if (won) 1 else 0;
        let initial_level = calculate_level(games_won, 1);

        let badge = ReputationBadge {
            id: object::new(ctx),
            player,
            games_played: 1,
            games_won,
            total_points: initial_points,
            citizen_wins: if (won && role_was_citizen) 1 else 0,
            saboteur_wins: if (won && !role_was_citizen) 1 else 0,
            perfect_consensus_rounds: 0,
            times_eliminated: if (won) 0 else 1,
            level: initial_level,
            last_updated: timestamp,
        };

        let badge_id = object::id(&badge);

        event::emit(BadgeMinted {
            badge_id,
            player,
            initial_level,
        });

        // Register in global registry
        table::add(&mut registry.player_badges, player, badge_id);

        // Transfer badge to player (soul-bound - can't transfer further)
        transfer::transfer(badge, player);
    }

    /// Update existing badge with new game results
    public fun update_badge(
        badge: &mut ReputationBadge,
        points_earned: u64,
        won: bool,
        role_was_citizen: bool,
        timestamp: u64,
    ) {
        // Update games played
        badge.games_played = badge.games_played + 1;

        // Update win stats
        if (won) {
            badge.games_won = badge.games_won + 1;

            if (role_was_citizen) {
                badge.citizen_wins = badge.citizen_wins + 1;
            } else {
                badge.saboteur_wins = badge.saboteur_wins + 1;
            }
        } else {
            badge.times_eliminated = badge.times_eliminated + 1;
        };

        // Update points
        badge.total_points = badge.total_points + points_earned;

        // Recalculate level based on win rate
        badge.level = calculate_level(badge.games_won, badge.games_played);

        badge.last_updated = timestamp;

        event::emit(BadgeUpdated {
            badge_id: object::uid_to_inner(&badge.id),
            player: badge.player,
            games_played: badge.games_played,
            games_won: badge.games_won,
            new_level: badge.level,
            total_points: badge.total_points,
        });
    }

    /// Check if player has a badge registered
    public fun has_badge(registry: &BadgeRegistry, player: address): bool {
        table::contains(&registry.player_badges, player)
    }

    /// Get badge ID for a player
    public fun get_badge_id(registry: &BadgeRegistry, player: address): ID {
        assert!(table::contains(&registry.player_badges, player), EBadgeNotFound);
        *table::borrow(&registry.player_badges, player)
    }

    // === Helper Functions ===

    /// Calculate reputation level based on win rate
    fun calculate_level(wins: u64, games: u64): u8 {
        if (games == 0) return LEVEL_BRONZE;

        let win_rate = (wins * 100) / games;  // Percentage

        if (win_rate >= 80) {
            LEVEL_DIAMOND
        } else if (win_rate >= 60) {
            LEVEL_PLATINUM
        } else if (win_rate >= 40) {
            LEVEL_GOLD
        } else if (win_rate >= 20) {
            LEVEL_SILVER
        } else {
            LEVEL_BRONZE
        }
    }

    // === View Functions ===

    public fun get_badge_stats(badge: &ReputationBadge): (u64, u64, u64, u8) {
        (
            badge.games_played,
            badge.games_won,
            badge.total_points,
            badge.level
        )
    }

    public fun get_role_wins(badge: &ReputationBadge): (u64, u64) {
        (badge.citizen_wins, badge.saboteur_wins)
    }

    public fun get_badge_level(badge: &ReputationBadge): u8 {
        badge.level
    }

    public fun get_win_rate(badge: &ReputationBadge): u64 {
        if (badge.games_played == 0) return 0;
        (badge.games_won * 100) / badge.games_played
    }

    public fun get_player_address(badge: &ReputationBadge): address {
        badge.player
    }

    // === Constants Getters ===

    public fun level_bronze(): u8 { LEVEL_BRONZE }
    public fun level_silver(): u8 { LEVEL_SILVER }
    public fun level_gold(): u8 { LEVEL_GOLD }
    public fun level_platinum(): u8 { LEVEL_PLATINUM }
    public fun level_diamond(): u8 { LEVEL_DIAMOND }
}
