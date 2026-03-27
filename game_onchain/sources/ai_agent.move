module game_onchain::ai_agent {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::event;
    use one::table::{Self, Table};
    use one::clock::{Self, Clock};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::balance::{Self, Balance};
    use std::string::{Self, String};
    use std::vector;
    use std::hash;
    use std::bcs;

    // === Agent Classes ===
    const CLASS_SCOUT: u8 = 1;       // Fast exploration, resource detection
    const CLASS_BUILDER: u8 = 2;     // Structure construction bonuses
    const CLASS_MINER: u8 = 3;       // Resource harvesting bonuses
    const CLASS_GUARDIAN: u8 = 4;    // Territory defense bonuses
    const CLASS_SCIENTIST: u8 = 5;   // Data shard processing, upgrades
    const CLASS_TRADER: u8 = 6;      // Marketplace advantages

    // === Agent Rarities ===
    const RARITY_COMMON: u8 = 1;
    const RARITY_UNCOMMON: u8 = 2;
    const RARITY_RARE: u8 = 3;
    const RARITY_EPIC: u8 = 4;
    const RARITY_LEGENDARY: u8 = 5;

    // === Evolution Thresholds (XP) ===
    const EVOLVE_LEVEL_2: u64 = 100;
    const EVOLVE_LEVEL_3: u64 = 300;
    const EVOLVE_LEVEL_4: u64 = 600;
    const EVOLVE_LEVEL_5: u64 = 1000;
    const EVOLVE_LEVEL_6: u64 = 1500;
    const EVOLVE_LEVEL_7: u64 = 2500;
    const EVOLVE_LEVEL_8: u64 = 4000;
    const EVOLVE_LEVEL_9: u64 = 6000;
    const EVOLVE_LEVEL_10: u64 = 10000;

    // === Mint Costs ===
    const MINT_COST_COMMON: u64 = 10_000_000;     // 0.01 OCT
    const MINT_COST_UNCOMMON: u64 = 50_000_000;   // 0.05 OCT
    const MINT_COST_RARE: u64 = 200_000_000;      // 0.2 OCT
    const MINT_COST_EPIC: u64 = 500_000_000;      // 0.5 OCT
    const MINT_COST_LEGENDARY: u64 = 2_000_000_000; // 2 OCT

    // === Error Codes ===
    const EInvalidClass: u64 = 500;
    const EInvalidRarity: u64 = 501;
    const EInsufficientPayment: u64 = 502;
    const ENotAgentOwner: u64 = 503;
    const ECannotEvolve: u64 = 504;
    const EMaxLevelReached: u64 = 505;
    const EInsufficientResources: u64 = 506;
    const EInvalidName: u64 = 507;
    const EAgentLocked: u64 = 508;

    // === Structs ===

    /// AI Agent NFT - an AI entity in the world
    public struct AIAgent has key, store {
        id: UID,
        owner: address,
        // Identity
        name: String,
        agent_class: u8,
        rarity: u8,
        // Stats
        level: u8,
        xp: u64,
        // Class-specific bonuses
        harvest_bonus: u64,
        build_bonus: u64,
        defense_bonus: u64,
        exploration_bonus: u64,
        // Location (in world grid)
        location_x: u64,
        location_y: u64,
        is_deployed: bool,
        // Resource inventory
        resources: Table<u8, u64>, // resource_type -> amount
        // Experience tracking
        territories_explored: u64,
        resources_gathered: u64,
        structures_built: u64,
        missions_completed: u64,
        // Timestamps
        created_at: u64,
        last_explore: u64,
        last_active: u64,
        // DNA (deterministic traits from minting)
        dna: vector<u8>,
        // Locked state (for marketplace/trading)
        locked: bool,
    }

    /// Agent registry for global tracking
    public struct AgentRegistry has key {
        id: UID,
        total_agents: u64,
        agents_by_class: Table<u8, u64>,
        agents_by_rarity: Table<u8, u64>,
        agent_ids: vector<ID>,
    }

    // === Events ===

    public struct AgentRegistryCreated has copy, drop {
        registry_id: ID,
    }

    public struct AgentMinted has copy, drop {
        agent_id: ID,
        owner: address,
        name: String,
        agent_class: u8,
        rarity: u8,
        dna: vector<u8>,
        cost: u64,
    }

    public struct AgentEvolved has copy, drop {
        agent_id: ID,
        owner: address,
        old_level: u8,
        new_level: u8,
        xp_spent: u64,
    }

    public struct AgentRenamed has copy, drop {
        agent_id: ID,
        owner: address,
        old_name: String,
        new_name: String,
    }

    public struct AgentXPGained has copy, drop {
        agent_id: ID,
        xp_gained: u64,
        total_xp: u64,
        source: String,
    }

    public struct AgentTransferred has copy, drop {
        agent_id: ID,
        from: address,
        to: address,
    }

    public struct AgentLocked has copy, drop {
        agent_id: ID,
        owner: address,
        locked: bool,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let registry = AgentRegistry {
            id: object::new(ctx),
            total_agents: 0,
            agents_by_class: table::new(ctx),
            agents_by_rarity: table::new(ctx),
            agent_ids: vector::empty(),
        };

        // Initialize class counts
        let mut i = 1;
        while (i <= 6) {
            table::add(&mut registry.agents_by_class, i, 0);
            i = i + 1;
        };

        // Initialize rarity counts
        i = 1;
        while (i <= 5) {
            table::add(&mut registry.agents_by_rarity, i, 0);
            i = i + 1;
        };

        event::emit(AgentRegistryCreated {
            registry_id: object::id(&registry),
        });

        transfer::share_object(registry);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Minting ===

    /// Mint a new AI Agent
    public entry fun mint_agent(
        registry: &mut AgentRegistry,
        name: String,
        agent_class: u8,
        rarity: u8,
        mut payment: Coin<OCT>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(agent_class >= 1 && agent_class <= 6, EInvalidClass);
        assert!(rarity >= 1 && rarity <= 5, EInvalidRarity);
        assert!(string::length(&name) > 0 && string::length(&name) <= 32, EInvalidName);

        let cost = mint_cost(rarity);
        assert!(coin::value(&payment) >= cost, EInsufficientPayment);

        let sender = tx_context::sender(ctx);
        let timestamp = clock::timestamp_ms(clock);

        // Generate deterministic DNA
        let dna = generate_dna(sender, agent_class, rarity, timestamp);

        // Calculate initial stats based on class and rarity
        let (harvest_bonus, build_bonus, defense_bonus, exploration_bonus) = class_base_stats(
            agent_class, rarity
        );

        let agent = AIAgent {
            id: object::new(ctx),
            owner: sender,
            name,
            agent_class,
            rarity,
            level: 1,
            xp: 0,
            harvest_bonus,
            build_bonus,
            defense_bonus,
            exploration_bonus,
            location_x: 0,
            location_y: 0,
            is_deployed: false,
            resources: table::new(ctx),
            territories_explored: 0,
            resources_gathered: 0,
            structures_built: 0,
            missions_completed: 0,
            created_at: timestamp,
            last_explore: 0,
            last_active: timestamp,
            dna,
            locked: false,
        };

        let agent_id = object::id(&agent);

        // Update registry
        registry.total_agents = registry.total_agents + 1;
        vector::push_back(&mut registry.agent_ids, agent_id);

        let class_count = table::borrow_mut(&mut registry.agents_by_class, agent_class);
        *class_count = *class_count + 1;

        let rarity_count = table::borrow_mut(&mut registry.agents_by_rarity, rarity);
        *rarity_count = *rarity_count + 1;

        event::emit(AgentMinted {
            agent_id,
            owner: sender,
            name,
            agent_class,
            rarity,
            dna,
            cost,
        });

        // Transfer agent to minter
        transfer::transfer(agent, sender);

        // Handle payment - burn/lock it
        let _burned = coin::split(&mut payment, cost, ctx);
        // Return change
        transfer::public_transfer(payment, sender);
    }

    /// Generate deterministic DNA for agent traits
    fun generate_dna(owner: address, agent_class: u8, rarity: u8, timestamp: u64): vector<u8> {
        let mut data = vector::empty<u8>();
        vector::append(&mut data, bcs::to_bytes(&owner));
        vector::append(&mut data, bcs::to_bytes(&agent_class));
        vector::append(&mut data, bcs::to_bytes(&rarity));
        vector::append(&mut data, bcs::to_bytes(&timestamp));
        hash::sha3_256(data)
    }

    /// Calculate base stats for class and rarity
    fun class_base_stats(agent_class: u8, rarity: u8): (u64, u64, u64, u64) {
        let rarity_mult = (rarity as u64);

        // (harvest_bonus, build_bonus, defense_bonus, exploration_bonus)
        if (agent_class == CLASS_SCOUT) {
            (2 * rarity_mult, 0, 1 * rarity_mult, 5 * rarity_mult)
        } else if (agent_class == CLASS_BUILDER) {
            (1 * rarity_mult, 5 * rarity_mult, 2 * rarity_mult, 1 * rarity_mult)
        } else if (agent_class == CLASS_MINER) {
            (5 * rarity_mult, 1 * rarity_mult, 1 * rarity_mult, 1 * rarity_mult)
        } else if (agent_class == CLASS_GUARDIAN) {
            (1 * rarity_mult, 1 * rarity_mult, 5 * rarity_mult, 1 * rarity_mult)
        } else if (agent_class == CLASS_SCIENTIST) {
            (2 * rarity_mult, 3 * rarity_mult, 1 * rarity_mult, 3 * rarity_mult)
        } else if (agent_class == CLASS_TRADER) {
            (3 * rarity_mult, 1 * rarity_mult, 1 * rarity_mult, 2 * rarity_mult)
        } else {
            (1, 1, 1, 1)
        }
    }

    /// Get mint cost by rarity
    fun mint_cost(rarity: u8): u64 {
        if (rarity == RARITY_COMMON) MINT_COST_COMMON
        else if (rarity == RARITY_UNCOMMON) MINT_COST_UNCOMMON
        else if (rarity == RARITY_RARE) MINT_COST_RARE
        else if (rarity == RARITY_EPIC) MINT_COST_EPIC
        else if (rarity == RARITY_LEGENDARY) MINT_COST_LEGENDARY
        else MINT_COST_COMMON
    }

    // === Evolution ===

    /// Evolve agent to next level (requires XP threshold)
    public entry fun evolve_agent(
        agent: &mut AIAgent,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(agent.owner == sender, ENotAgentOwner);
        assert!(!agent.locked, EAgentLocked);
        assert!(agent.level < 10, EMaxLevelReached);

        let xp_required = evolution_threshold(agent.level + 1);
        assert!(agent.xp >= xp_required, ECannotEvolve);

        let old_level = agent.level;
        agent.xp = agent.xp - xp_required;
        agent.level = agent.level + 1;

        // Boost stats on evolution
        let rarity_mult = (agent.rarity as u64);
        agent.harvest_bonus = agent.harvest_bonus + rarity_mult;
        agent.build_bonus = agent.build_bonus + rarity_mult;
        agent.defense_bonus = agent.defense_bonus + rarity_mult;
        agent.exploration_bonus = agent.exploration_bonus + rarity_mult;

        agent.last_active = clock::timestamp_ms(clock);

        event::emit(AgentEvolved {
            agent_id: object::uid_to_inner(&agent.id),
            owner: sender,
            old_level,
            new_level: agent.level,
            xp_spent: xp_required,
        });
    }

    /// Get XP threshold for a given level
    fun evolution_threshold(level: u8): u64 {
        if (level == 2) EVOLVE_LEVEL_2
        else if (level == 3) EVOLVE_LEVEL_3
        else if (level == 4) EVOLVE_LEVEL_4
        else if (level == 5) EVOLVE_LEVEL_5
        else if (level == 6) EVOLVE_LEVEL_6
        else if (level == 7) EVOLVE_LEVEL_7
        else if (level == 8) EVOLVE_LEVEL_8
        else if (level == 9) EVOLVE_LEVEL_9
        else if (level == 10) EVOLVE_LEVEL_10
        else 0
    }

    // === XP Management ===

    /// Add XP to agent
    public fun add_xp(agent: &mut AIAgent, amount: u64, source: String) {
        agent.xp = agent.xp + amount;

        event::emit(AgentXPGained {
            agent_id: object::uid_to_inner(&agent.id),
            xp_gained: amount,
            total_xp: agent.xp,
            source,
        });
    }

    // === Resource Management ===

    /// Add resource to agent inventory
    public fun add_resource(agent: &mut AIAgent, resource_type: u8, amount: u64) {
        if (table::contains(&agent.resources, resource_type)) {
            let current = table::borrow_mut(&mut agent.resources, resource_type);
            *current = *current + amount;
        } else {
            table::add(&mut agent.resources, resource_type, amount);
        };
        agent.resources_gathered = agent.resources_gathered + amount;
    }

    /// Remove resource from agent inventory
    public fun remove_resource(agent: &mut AIAgent, resource_type: u8, amount: u64) {
        assert!(table::contains(&agent.resources, resource_type), EInsufficientResources);
        let current = table::borrow_mut(&mut agent.resources, resource_type);
        assert!(*current >= amount, EInsufficientResources);
        *current = *current - amount;
    }

    /// Check if agent has enough resources
    public fun has_resources(agent: &AIAgent, resource_type: u8, amount: u64): bool {
        if (!table::contains(&agent.resources, resource_type)) {
            amount == 0
        } else {
            *table::borrow(&agent.resources, resource_type) >= amount
        }
    }

    /// Get resource amount
    public fun get_resource(agent: &AIAgent, resource_type: u8): u64 {
        if (!table::contains(&agent.resources, resource_type)) {
            0
        } else {
            *table::borrow(&agent.resources, resource_type)
        }
    }

    // === Location Management ===

    /// Set agent location (called by world module)
    public fun set_location(agent: &mut AIAgent, x: u64, y: u64) {
        agent.location_x = x;
        agent.location_y = y;
        agent.is_deployed = true;
    }

    /// Set last exploration timestamp
    public fun set_last_explore(agent: &mut AIAgent, timestamp: u64) {
        agent.last_explore = timestamp;
    }

    // === Rename ===

    /// Rename agent
    public entry fun rename_agent(
        agent: &mut AIAgent,
        new_name: String,
        clock: &Clock,
        ctx: &TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(agent.owner == sender, ENotAgentOwner);
        assert!(!agent.locked, EAgentLocked);
        assert!(string::length(&new_name) > 0 && string::length(&new_name) <= 32, EInvalidName);

        let old_name = agent.name;
        agent.name = new_name;
        agent.last_active = clock::timestamp_ms(clock);

        event::emit(AgentRenamed {
            agent_id: object::uid_to_inner(&agent.id),
            owner: sender,
            old_name,
            new_name,
        });
    }

    // === Locking ===

    /// Lock/unlock agent (for marketplace)
    public fun set_locked(agent: &mut AIAgent, locked: bool, ctx: &TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(agent.owner == sender, ENotAgentOwner);
        agent.locked = locked;

        event::emit(AgentLocked {
            agent_id: object::uid_to_inner(&agent.id),
            owner: sender,
            locked,
        });
    }

    // === View Functions ===

    public fun get_id(agent: &AIAgent): ID {
        object::uid_to_inner(&agent.id)
    }

    public fun get_owner(agent: &AIAgent): address {
        agent.owner
    }

    public fun get_name(agent: &AIAgent): &String {
        &agent.name
    }

    public fun get_class(agent: &AIAgent): u8 {
        agent.agent_class
    }

    public fun get_rarity(agent: &AIAgent): u8 {
        agent.rarity
    }

    public fun get_level(agent: &AIAgent): u8 {
        agent.level
    }

    public fun get_xp(agent: &AIAgent): u64 {
        agent.xp
    }

    public fun get_harvest_bonus(agent: &AIAgent): u64 {
        agent.harvest_bonus
    }

    public fun get_build_bonus(agent: &AIAgent): u64 {
        agent.build_bonus
    }

    public fun get_defense_bonus(agent: &AIAgent): u64 {
        agent.defense_bonus
    }

    public fun get_exploration_bonus(agent: &AIAgent): u64 {
        agent.exploration_bonus
    }

    public fun get_last_explore(agent: &AIAgent): u64 {
        agent.last_explore
    }

    public fun get_stats(agent: &AIAgent): (u8, u8, u8, u64, u64, u64, u64, u64) {
        (
            agent.agent_class,
            agent.rarity,
            agent.level,
            agent.xp,
            agent.harvest_bonus,
            agent.build_bonus,
            agent.defense_bonus,
            agent.exploration_bonus
        )
    }

    public fun get_activity_stats(agent: &AIAgent): (u64, u64, u64, u64) {
        (
            agent.territories_explored,
            agent.resources_gathered,
            agent.structures_built,
            agent.missions_completed
        )
    }

    public fun is_deployed(agent: &AIAgent): bool {
        agent.is_deployed
    }

    public fun is_locked(agent: &AIAgent): bool {
        agent.locked
    }

    public fun get_dna(agent: &AIAgent): &vector<u8> {
        &agent.dna
    }

    // === Constants Getters ===
    public fun class_scout(): u8 { CLASS_SCOUT }
    public fun class_builder(): u8 { CLASS_BUILDER }
    public fun class_miner(): u8 { CLASS_MINER }
    public fun class_guardian(): u8 { CLASS_GUARDIAN }
    public fun class_scientist(): u8 { CLASS_SCIENTIST }
    public fun class_trader(): u8 { CLASS_TRADER }
    public fun rarity_common(): u8 { RARITY_COMMON }
    public fun rarity_uncommon(): u8 { RARITY_UNCOMMON }
    public fun rarity_rare(): u8 { RARITY_RARE }
    public fun rarity_epic(): u8 { RARITY_EPIC }
    public fun rarity_legendary(): u8 { RARITY_LEGENDARY }
}
