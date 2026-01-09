module game_onchain::role_machine {
    use one::object::{Self, UID};
    use one::tx_context::{Self, TxContext};
    use one::clock::{Self, Clock};
    use one::event;
    use one::table::{Self, Table};
    use std::vector;
    use std::hash;
    use std::bcs;

    // === Role Constants ===
    const ROLE_CITIZEN: u8 = 1;
    const ROLE_SABOTEUR: u8 = 2;

    // Saboteur ratio: 1 saboteur per 3 players (33%)
    const SABOTEUR_RATIO_NUMERATOR: u64 = 1;
    const SABOTEUR_RATIO_DENOMINATOR: u64 = 3;

    // Consensus threshold: 50% of alive players
    const CONSENSUS_THRESHOLD_PERCENT: u64 = 50;

    // === Error Codes ===
    const ERoleNotRevealed: u64 = 100;
    const EInvalidRole: u64 = 101;
    const ENotEnoughPlayers: u64 = 102;

    // === Structs ===

    /// Role assignment manager
    public struct RoleMachine has store {
        player_roles: Table<address, u8>,        // Secret role storage
        role_revealed: Table<address, bool>,     // Track who revealed their role
        saboteur_count: u64,
        citizen_count: u64,
        assignment_seed: vector<u8>,             // Seed used for role assignment
    }

    // === Events ===

    public struct RolesAssigned has copy, drop {
        total_players: u64,
        citizen_count: u64,
        saboteur_count: u64,
        assignment_hash: vector<u8>,
    }

    public struct RoleRevealed has copy, drop {
        player: address,
        role: u8,
    }

    public struct ConsensusChecked has copy, drop {
        round: u64,
        max_votes: u64,
        threshold: u64,
        consensus_reached: bool,
    }

    public struct WinConditionChecked has copy, drop {
        citizens_alive: u64,
        saboteurs_alive: u64,
        winner: u8, // 0=none, 1=citizens, 2=saboteurs
    }

    // === Public Functions ===

    /// Create new RoleMachine
    public fun new(ctx: &mut TxContext): RoleMachine {
        RoleMachine {
            player_roles: table::new(ctx),
            role_revealed: table::new(ctx),
            saboteur_count: 0,
            citizen_count: 0,
            assignment_seed: vector::empty(),
        }
    }

    /// Assign roles to players using deterministic randomization
    public fun assign_roles(
        machine: &mut RoleMachine,
        players: &vector<address>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let player_count = vector::length(players);
        assert!(player_count >= 2, ENotEnoughPlayers);

        // Calculate saboteur count (1 per 3 players, minimum 1 if >= 3 players)
        let saboteur_count = if (player_count >= 3) {
            (player_count * SABOTEUR_RATIO_NUMERATOR) / SABOTEUR_RATIO_DENOMINATOR
        } else {
            0 // No saboteurs for 2 player games
        };

        let citizen_count = player_count - saboteur_count;

        // Generate deterministic but unpredictable seed
        let timestamp = clock::timestamp_ms(clock);
        let epoch = tx_context::epoch(ctx);
        let sender = tx_context::sender(ctx);

        let mut seed_data = vector::empty<u8>();
        vector::append(&mut seed_data, bcs::to_bytes(&timestamp));
        vector::append(&mut seed_data, bcs::to_bytes(&epoch));
        vector::append(&mut seed_data, bcs::to_bytes(&sender));
        vector::append(&mut seed_data, bcs::to_bytes(&player_count));

        let seed = hash::sha3_256(seed_data);
        machine.assignment_seed = seed;

        // Assign roles using Fisher-Yates shuffle with hash-based randomness
        let mut role_pool = vector::empty<u8>();

        // Fill pool with saboteur roles
        let mut i = 0;
        while (i < saboteur_count) {
            vector::push_back(&mut role_pool, ROLE_SABOTEUR);
            i = i + 1;
        };

        // Fill pool with citizen roles
        i = 0;
        while (i < citizen_count) {
            vector::push_back(&mut role_pool, ROLE_CITIZEN);
            i = i + 1;
        };

        // Shuffle role pool using seed
        shuffle_roles(&mut role_pool, &seed);

        // Assign shuffled roles to players
        i = 0;
        while (i < player_count) {
            let player = vector::borrow(players, i);
            let role = *vector::borrow(&role_pool, i);

            table::add(&mut machine.player_roles, *player, role);
            table::add(&mut machine.role_revealed, *player, false);

            i = i + 1;
        };

        machine.saboteur_count = saboteur_count;
        machine.citizen_count = citizen_count;

        event::emit(RolesAssigned {
            total_players: player_count,
            citizen_count,
            saboteur_count,
            assignment_hash: seed,
        });
    }

    /// Player reveals their own role (only they can see it)
    public fun reveal_my_role(
        machine: &mut RoleMachine,
        ctx: &TxContext
    ): u8 {
        let player = tx_context::sender(ctx);
        let role = *table::borrow(&machine.player_roles, player);

        // Mark as revealed
        if (table::contains(&machine.role_revealed, player)) {
            *table::borrow_mut(&mut machine.role_revealed, player) = true;
        };

        event::emit(RoleRevealed {
            player,
            role,
        });

        role
    }

    /// Check if consensus was reached in a vote
    public fun check_consensus(
        alive_count: u64,
        option_1_votes: u64,
        option_2_votes: u64,
        option_3_votes: u64,
        round: u64,
    ): bool {
        // Consensus threshold: 50% of alive players
        let threshold = (alive_count * CONSENSUS_THRESHOLD_PERCENT + 99) / 100; // Ceiling

        let max_votes = max_of_three(option_1_votes, option_2_votes, option_3_votes);
        let consensus_reached = max_votes >= threshold;

        event::emit(ConsensusChecked {
            round,
            max_votes,
            threshold,
            consensus_reached,
        });

        consensus_reached
    }

    /// Check win conditions based on role distribution and consensus tracking
    public fun check_win_condition(
        machine: &RoleMachine,
        survivors: &vector<address>,
        current_round: u64,
        max_rounds: u64,
        rounds_without_consensus: u64,
    ): u8 {
        let (citizen_count, saboteur_count) = count_roles_in_survivors(machine, survivors);

        // Citizens win if all saboteurs eliminated
        if (saboteur_count == 0 && citizen_count > 0) {
            event::emit(WinConditionChecked {
                citizens_alive: citizen_count,
                saboteurs_alive: saboteur_count,
                winner: ROLE_CITIZEN,
            });
            return ROLE_CITIZEN
        };

        // Saboteurs win if they control >= 50% of survivors
        if (saboteur_count > 0 && saboteur_count >= citizen_count) {
            event::emit(WinConditionChecked {
                citizens_alive: citizen_count,
                saboteurs_alive: saboteur_count,
                winner: ROLE_SABOTEUR,
            });
            return ROLE_SABOTEUR
        };

        // Saboteurs win if they prevented consensus for 2+ consecutive rounds
        // This is their primary win condition: disrupting group cohesion
        if (saboteur_count > 0 && rounds_without_consensus >= 2) {
            event::emit(WinConditionChecked {
                citizens_alive: citizen_count,
                saboteurs_alive: saboteur_count,
                winner: ROLE_SABOTEUR,
            });
            return ROLE_SABOTEUR
        };

        // Saboteurs win if max rounds reached without citizen victory
        if (current_round >= max_rounds && saboteur_count > 0) {
            event::emit(WinConditionChecked {
                citizens_alive: citizen_count,
                saboteurs_alive: saboteur_count,
                winner: ROLE_SABOTEUR,
            });
            return ROLE_SABOTEUR
        };

        // Game continues
        event::emit(WinConditionChecked {
            citizens_alive: citizen_count,
            saboteurs_alive: saboteur_count,
            winner: 0,
        });

        0 // No winner yet
    }

    /// Get role of a specific player (only after game ends)
    public fun get_player_role(machine: &RoleMachine, player: address): u8 {
        *table::borrow(&machine.player_roles, player)
    }

    /// Check if player has specific role
    public fun is_role(machine: &RoleMachine, player: address, role: u8): bool {
        *table::borrow(&machine.player_roles, player) == role
    }

    /// Get role distribution
    public fun get_role_distribution(machine: &RoleMachine): (u64, u64) {
        (machine.citizen_count, machine.saboteur_count)
    }

    /// Check if player revealed their role
    public fun has_revealed_role(machine: &RoleMachine, player: address): bool {
        *table::borrow(&machine.role_revealed, player)
    }

    // === Helper Functions ===

    /// Count roles among survivors
    fun count_roles_in_survivors(
        machine: &RoleMachine,
        survivors: &vector<address>
    ): (u64, u64) {
        let mut citizen_count = 0u64;
        let mut saboteur_count = 0u64;

        let len = vector::length(survivors);
        let mut i = 0;

        while (i < len) {
            let player = vector::borrow(survivors, i);
            let role = table::borrow(&machine.player_roles, *player);

            if (*role == ROLE_CITIZEN) {
                citizen_count = citizen_count + 1;
            } else if (*role == ROLE_SABOTEUR) {
                saboteur_count = saboteur_count + 1;
            };

            i = i + 1;
        };

        (citizen_count, saboteur_count)
    }

    /// Shuffle roles using hash-based randomness
    fun shuffle_roles(roles: &mut vector<u8>, seed: &vector<u8>) {
        let len = vector::length(roles);
        if (len <= 1) return;

        let mut i = len - 1;
        while (i > 0) {
            // Generate random index using hash
            let mut hash_input = *seed;
            vector::append(&mut hash_input, bcs::to_bytes(&i));
            let hash_output = hash::sha3_256(hash_input);

            // Use first 8 bytes as random number
            let random_value = bytes_to_u64(&hash_output);
            let j = random_value % (i + 1);

            // Swap roles[i] with roles[j]
            let temp = *vector::borrow(roles, i);
            *vector::borrow_mut(roles, i) = *vector::borrow(roles, j);
            *vector::borrow_mut(roles, j) = temp;

            i = i - 1;
        };
    }

    /// Convert first 8 bytes of vector to u64
    fun bytes_to_u64(bytes: &vector<u8>): u64 {
        let mut result = 0u64;
        let mut i = 0u64;

        while (i < 8 && i < vector::length(bytes)) {
            let byte = *vector::borrow(bytes, i);
            let shift_amount = (i * 8) as u8;
            result = result | ((byte as u64) << shift_amount);
            i = i + 1;
        };

        result
    }

    /// Find maximum of three values
    fun max_of_three(a: u64, b: u64, c: u64): u64 {
        let mut max = a;
        if (b > max) max = b;
        if (c > max) max = c;
        max
    }

    // === Constants Getters ===

    public fun role_citizen(): u8 { ROLE_CITIZEN }
    public fun role_saboteur(): u8 { ROLE_SABOTEUR }
    public fun consensus_threshold_percent(): u64 { CONSENSUS_THRESHOLD_PERCENT }
}
