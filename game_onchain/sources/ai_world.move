module game_onchain::ai_world {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::event;
    use one::table::{Self, Table};
    use one::clock::{Self, Clock};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::balance::{Self, Balance};
    use std::string::String;
    use std::vector;
    use game_onchain::ai_agent::{Self, AIAgent};

    // === Constants ===

    // World grid dimensions
    const WORLD_WIDTH: u64 = 64;
    const WORLD_HEIGHT: u64 = 64;

    // Terrain types
    const TERRAIN_PLAINS: u8 = 0;
    const TERRAIN_FOREST: u8 = 1;
    const TERRAIN_MOUNTAIN: u8 = 2;
    const TERRAIN_WATER: u8 = 3;
    const TERRAIN_DESERT: u8 = 4;
    const TERRAIN_CRYSTAL_CAVE: u8 = 5;

    // Resource types
    const RESOURCE_NONE: u8 = 0;
    const RESOURCE_WOOD: u8 = 1;
    const RESOURCE_STONE: u8 = 2;
    const RESOURCE_IRON: u8 = 3;
    const RESOURCE_CRYSTAL: u8 = 4;
    const RESOURCE_ENERGY: u8 = 5;
    const RESOURCE_DATA_SHARD: u8 = 6;

    // Territory costs by terrain (in OCT MIST)
    const COST_PLAINS: u64 = 5_000_000;       // 0.005 OCT
    const COST_FOREST: u64 = 10_000_000;      // 0.01 OCT
    const COST_MOUNTAIN: u64 = 20_000_000;    // 0.02 OCT
    const COST_WATER: u64 = 15_000_000;       // 0.015 OCT
    const COST_DESERT: u64 = 8_000_000;       // 0.008 OCT
    const COST_CRYSTAL_CAVE: u64 = 50_000_000; // 0.05 OCT

    // World treasury fee (3%)
    const WORLD_FEE_BPS: u64 = 300;

    // Max territories per agent
    const MAX_TERRITORIES_PER_AGENT: u64 = 10;

    // Cooldowns (in milliseconds)
    const HARVEST_COOLDOWN_MS: u64 = 300_000;    // 5 minutes
    const EXPLORATION_COOLDOWN_MS: u64 = 180_000; // 3 minutes

    // === Error Codes ===
    const EOutOfBounds: u64 = 400;
    const ETerritoryClaimed: u64 = 401;
    const ENotTerritoryOwner: u64 = 402;
    const EInsufficientPayment: u64 = 403;
    const EMaxTerritoriesReached: u64 = 404;
    const EAgentNotInTerritory: u64 = 405;
    const EHarvestCooldown: u64 = 406;
    const EExplorationCooldown: u64 = 407;
    const ENoResourcesToHarvest: u64 = 408;
    const EAgentNotOwned: u64 = 409;
    const EInvalidTerrain: u64 = 410;
    const EWorldNotInitialized: u64 = 411;
    const EAgentAlreadyPlaced: u64 = 412;

    // === Structs ===

    /// The AI World - shared global state
    public struct AIWorld has key {
        id: UID,
        width: u64,
        height: u64,
        // Territory grid: coordinates -> territory data
        territories: Table<u64, Territory>,
        // Player agent tracking
        player_agents: Table<address, vector<ID>>,
        // Agent location tracking: agent_id -> coordinates
        agent_locations: Table<ID, u64>,
        // World treasury
        treasury: Balance<OCT>,
        // World stats
        total_territories_claimed: u64,
        total_agents_created: u64,
        total_resources_harvested: u64,
        // Creation timestamp
        created_at: u64,
        // Season tracking
        current_season: u64,
    }

    /// Territory data (stored in grid)
    public struct Territory has store {
        x: u64,
        y: u64,
        terrain: u8,
        // Resource availability (regenerates over time)
        resource_type: u8,
        resource_amount: u64,
        max_resources: u64,
        // Ownership
        owner: address,
        is_claimed: bool,
        claimed_at: u64,
        // Structures built on territory
        structure: u8, // 0=none, 1=outpost, 2=lab, 3=fortress, 4=data_center
        structure_level: u8,
        // Defense
        defense_rating: u64,
        // Last harvest timestamp
        last_harvest: u64,
    }

    /// Structure blueprint
    public struct StructureBlueprint has key, store {
        id: UID,
        structure_type: u8,
        level: u8,
        // Construction cost
        wood_cost: u64,
        stone_cost: u64,
        iron_cost: u64,
        crystal_cost: u64,
        // Benefits
        defense_bonus: u64,
        resource_bonus: u64,
        // Build time
        build_time_ms: u64,
    }

    // === Events ===

    public struct WorldCreated has copy, drop {
        world_id: ID,
        width: u64,
        height: u64,
        timestamp: u64,
    }

    public struct TerritoryClaimed has copy, drop {
        world_id: ID,
        owner: address,
        x: u64,
        y: u64,
        terrain: u8,
        cost: u64,
    }

    public struct TerritoryLost has copy, drop {
        world_id: ID,
        previous_owner: address,
        new_owner: address,
        x: u64,
        y: u64,
    }

    public struct AgentDeployed has copy, drop {
        world_id: ID,
        agent_id: ID,
        owner: address,
        x: u64,
        y: u64,
    }

    public struct AgentMoved has copy, drop {
        world_id: ID,
        agent_id: ID,
        from_x: u64,
        from_y: u64,
        to_x: u64,
        to_y: u64,
    }

    public struct ResourcesHarvested has copy, drop {
        world_id: ID,
        agent_id: ID,
        owner: address,
        x: u64,
        y: u64,
        resource_type: u8,
        amount: u64,
    }

    public struct StructureBuilt has copy, drop {
        world_id: ID,
        owner: address,
        x: u64,
        y: u64,
        structure_type: u8,
        level: u8,
    }

    public struct StructureUpgraded has copy, drop {
        world_id: ID,
        owner: address,
        x: u64,
        y: u64,
        structure_type: u8,
        new_level: u8,
    }

    public struct TerritoryExplored has copy, drop {
        world_id: ID,
        agent_id: ID,
        x: u64,
        y: u64,
        terrain: u8,
        resource_type: u8,
        resource_amount: u64,
    }

    public struct WorldSeasonAdvanced has copy, drop {
        world_id: ID,
        new_season: u64,
        timestamp: u64,
    }

    public struct ResourcesRegenerated has copy, drop {
        world_id: ID,
        territories_updated: u64,
    }

    // === Initialization ===

    /// Initialize the AI World
    entry fun init_world(clock: &Clock, ctx: &mut TxContext) {
        let world = AIWorld {
            id: object::new(ctx),
            width: WORLD_WIDTH,
            height: WORLD_HEIGHT,
            territories: table::new(ctx),
            player_agents: table::new(ctx),
            agent_locations: table::new(ctx),
            treasury: balance::zero(),
            total_territories_claimed: 0,
            total_agents_created: 0,
            total_resources_harvested: 0,
            created_at: clock::timestamp_ms(clock),
            current_season: 1,
        };

        // Generate initial terrain
        generate_terrain(&mut world);

        event::emit(WorldCreated {
            world_id: object::id(&world),
            width: WORLD_WIDTH,
            height: WORLD_HEIGHT,
            timestamp: clock::timestamp_ms(clock),
        });

        transfer::share_object(world);
    }

    #[test_only]
    public fun init_world_for_testing(clock: &Clock, ctx: &mut TxContext) {
        init_world(clock, ctx);
    }

    /// Generate initial terrain for the world grid
    fun generate_terrain(world: &mut AIWorld) {
        let mut y = 0;
        while (y < WORLD_HEIGHT) {
            let mut x = 0;
            while (x < WORLD_WIDTH) {
                let coord = coords_to_index(x, y);
                let terrain = generate_terrain_type(x, y);
                let (resource_type, max_res) = terrain_resources(terrain);

                let territory = Territory {
                    x,
                    y,
                    terrain,
                    resource_type,
                    resource_amount: max_res,
                    max_resources: max_res,
                    owner: @0x0,
                    is_claimed: false,
                    claimed_at: 0,
                    structure: 0,
                    structure_level: 0,
                    defense_rating: 0,
                    last_harvest: 0,
                };

                table::add(&mut world.territories, coord, territory);
                x = x + 1;
            };
            y = y + 1;
        };
    }

    /// Deterministic terrain generation based on coordinates
    fun generate_terrain_type(x: u64, y: u64): u8 {
        let hash_val = ((x * 7 + y * 13) + (x * y * 31)) % 100;
        if (hash_val < 30) TERRAIN_PLAINS
        else if (hash_val < 55) TERRAIN_FOREST
        else if (hash_val < 70) TERRAIN_MOUNTAIN
        else if (hash_val < 80) TERRAIN_WATER
        else if (hash_val < 92) TERRAIN_DESERT
        else TERRAIN_CRYSTAL_CAVE
    }

    /// Get resource type and max amount for terrain
    fun terrain_resources(terrain: u8): (u8, u64) {
        if (terrain == TERRAIN_PLAINS) (RESOURCE_ENERGY, 100)
        else if (terrain == TERRAIN_FOREST) (RESOURCE_WOOD, 150)
        else if (terrain == TERRAIN_MOUNTAIN) (RESOURCE_IRON, 80)
        else if (terrain == TERRAIN_WATER) (RESOURCE_DATA_SHARD, 60)
        else if (terrain == TERRAIN_DESERT) (RESOURCE_STONE, 120)
        else if (terrain == TERRAIN_CRYSTAL_CAVE) (RESOURCE_CRYSTAL, 40)
        else (RESOURCE_NONE, 0)
    }

    /// Get territory claim cost by terrain
    fun claim_cost(terrain: u8): u64 {
        if (terrain == TERRAIN_PLAINS) COST_PLAINS
        else if (terrain == TERRAIN_FOREST) COST_FOREST
        else if (terrain == TERRAIN_MOUNTAIN) COST_MOUNTAIN
        else if (terrain == TERRAIN_WATER) COST_WATER
        else if (terrain == TERRAIN_DESERT) COST_DESERT
        else if (terrain == TERRAIN_CRYSTAL_CAVE) COST_CRYSTAL_CAVE
        else COST_PLAINS
    }

    // === Coordinate Helpers ===

    fun coords_to_index(x: u64, y: u64): u64 {
        y * WORLD_WIDTH + x
    }

    fun index_to_coords(index: u64): (u64, u64) {
        (index % WORLD_WIDTH, index / WORLD_WIDTH)
    }

    fun validate_coords(x: u64, y: u64): bool {
        x < WORLD_WIDTH && y < WORLD_HEIGHT
    }

    /// Check if two coordinates are adjacent (4-directional)
    fun is_adjacent(x1: u64, y1: u64, x2: u64, y2: u64): bool {
        let dx = if (x1 > x2) x1 - x2 else x2 - x1;
        let dy = if (y1 > y2) y1 - y2 else y2 - y1;
        (dx == 1 && dy == 0) || (dx == 0 && dy == 1)
    }

    // === Territory Management ===

    /// Claim a territory in the world
    entry fun claim_territory(
        world: &mut AIWorld,
        x: u64,
        y: u64,
        mut payment: Coin<OCT>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(validate_coords(x, y), EOutOfBounds);

        let coord = coords_to_index(x, y);
        let territory = table::borrow_mut(&mut world.territories, coord);

        assert!(!territory.is_claimed, ETerritoryClaimed);

        let cost = claim_cost(territory.terrain);
        assert!(coin::value(&payment) >= cost, EInsufficientPayment);

        let sender = tx_context::sender(ctx);

        // Check max territories per player
        let current_count = count_player_territories(world, sender);
        assert!(current_count < MAX_TERRITORIES_PER_AGENT, EMaxTerritoriesReached);

        // Take payment: fee to treasury, rest burned/locked
        let fee = (cost * WORLD_FEE_BPS) / 10000;
        let fee_coin = coin::split(&mut payment, fee, ctx);
        balance::join(&mut world.treasury, coin::into_balance(fee_coin));

        // Deduct remaining from payment
        let remaining_cost = cost - fee;
        let _payment_coin = coin::split(&mut payment, remaining_cost, ctx);

        // Claim territory
        territory.owner = sender;
        territory.is_claimed = true;
        territory.claimed_at = clock::timestamp_ms(clock);

        world.total_territories_claimed = world.total_territories_claimed + 1;

        event::emit(TerritoryClaimed {
            world_id: object::id(world),
            owner: sender,
            x,
            y,
            terrain: territory.terrain,
            cost,
        });

        // Return change
        transfer::public_transfer(payment, sender);
    }

    /// Count territories owned by a player
    fun count_player_territories(world: &AIWorld, player: address): u64 {
        let mut count = 0;
        let total = WORLD_WIDTH * WORLD_HEIGHT;
        let mut i = 0;
        while (i < total) {
            if (table::contains(&world.territories, i)) {
                let territory = table::borrow(&world.territories, i);
                if (territory.is_claimed && territory.owner == player) {
                    count = count + 1;
                };
            };
            i = i + 1;
        };
        count
    }

    // === Agent Deployment ===

    /// Deploy an AI agent to a claimed territory
    entry fun deploy_agent(
        world: &mut AIWorld,
        agent: &mut AIAgent,
        x: u64,
        y: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(validate_coords(x, y), EOutOfBounds);

        let coord = coords_to_index(x, y);
        let territory = table::borrow(&world.territories, coord);

        let sender = tx_context::sender(ctx);

        // Verify territory is owned by sender
        assert!(territory.is_claimed && territory.owner == sender, ENotTerritoryOwner);

        // Verify agent is owned by sender
        assert!(ai_agent::get_owner(agent) == sender, EAgentNotOwned);

        let agent_id = ai_agent::get_id(agent);

        // Check if agent already deployed
        assert!(!table::contains(&world.agent_locations, agent_id), EAgentAlreadyPlaced);

        // Place agent
        table::add(&mut world.agent_locations, agent_id, coord);
        ai_agent::set_location(agent, x, y);

        world.total_agents_created = world.total_agents_created + 1;

        event::emit(AgentDeployed {
            world_id: object::id(world),
            agent_id,
            owner: sender,
            x,
            y,
        });
    }

    /// Move agent to adjacent territory
    entry fun move_agent(
        world: &mut AIWorld,
        agent: &mut AIAgent,
        to_x: u64,
        to_y: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(validate_coords(to_x, to_y), EOutOfBounds);

        let sender = tx_context::sender(ctx);
        assert!(ai_agent::get_owner(agent) == sender, EAgentNotOwned);

        let agent_id = ai_agent::get_id(agent);
        assert!(table::contains(&world.agent_locations, agent_id), EAgentNotInTerritory);

        let from_coord = *table::borrow(&world.agent_locations, agent_id);
        let (from_x, from_y) = index_to_coords(from_coord);

        // Check adjacency
        assert!(is_adjacent(from_x, from_y, to_x, to_y), EOutOfBounds);

        // Check target terrain is not water (agents can't walk on water)
        let to_coord = coords_to_index(to_x, to_y);
        let target_territory = table::borrow(&world.territories, to_coord);
        assert!(target_territory.terrain != TERRAIN_WATER, EInvalidTerrain);

        // Update location
        *table::borrow_mut(&mut world.agent_locations, agent_id) = to_coord;
        ai_agent::set_location(agent, to_x, to_y);

        event::emit(AgentMoved {
            world_id: object::id(world),
            agent_id,
            from_x,
            from_y,
            to_x,
            to_y,
        });
    }

    // === Resource Harvesting ===

    /// Harvest resources from territory where agent is located
    entry fun harvest_resources(
        world: &mut AIWorld,
        agent: &mut AIAgent,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(ai_agent::get_owner(agent) == sender, EAgentNotOwned);

        let agent_id = ai_agent::get_id(agent);
        assert!(table::contains(&world.agent_locations, agent_id), EAgentNotInTerritory);

        let coord = *table::borrow(&world.agent_locations, agent_id);
        let territory = table::borrow_mut(&mut world.territories, coord);

        let current_time = clock::timestamp_ms(clock);

        // Check harvest cooldown
        assert!(
            current_time >= territory.last_harvest + HARVEST_COOLDOWN_MS,
            EHarvestCooldown
        );

        // Check resources available
        assert!(territory.resource_amount > 0, ENoResourcesToHarvest);

        // Calculate harvest amount based on agent skill
        let base_harvest = 10;
        let skill_bonus = ai_agent::get_harvest_bonus(agent);
        let harvest_amount = base_harvest + skill_bonus;

        // Cap at available resources
        let actual_harvest = if (harvest_amount > territory.resource_amount) {
            territory.resource_amount
        } else {
            harvest_amount
        };

        // Update territory resources
        territory.resource_amount = territory.resource_amount - actual_harvest;
        territory.last_harvest = current_time;

        // Add resources to agent inventory
        ai_agent::add_resource(agent, territory.resource_type, actual_harvest);

        world.total_resources_harvested = world.total_resources_harvested + actual_harvest;

        event::emit(ResourcesHarvested {
            world_id: object::id(world),
            agent_id,
            owner: sender,
            x: territory.x,
            y: territory.y,
            resource_type: territory.resource_type,
            amount: actual_harvest,
        });
    }

    /// Regenerate resources across the world (can be called periodically)
    entry fun regenerate_resources(
        world: &mut AIWorld,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let mut updated = 0;
        let total = WORLD_WIDTH * WORLD_HEIGHT;
        let mut i = 0;

        while (i < total) {
            if (table::contains(&world.territories, i)) {
                let territory = table::borrow_mut(&mut world.territories, i);
                // Regenerate 10% of max resources per cycle
                let regen_amount = territory.max_resources / 10;
                if (territory.resource_amount < territory.max_resources) {
                    let new_amount = territory.resource_amount + regen_amount;
                    territory.resource_amount = if (new_amount > territory.max_resources) {
                        territory.max_resources
                    } else {
                        new_amount
                    };
                    updated = updated + 1;
                };
            };
            i = i + 1;
        };

        event::emit(ResourcesRegenerated {
            world_id: object::id(world),
            territories_updated: updated,
        });
    }

    // === Structure Building ===

    /// Build a structure on a claimed territory
    entry fun build_structure(
        world: &mut AIWorld,
        agent: &mut AIAgent,
        x: u64,
        y: u64,
        structure_type: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(validate_coords(x, y), EOutOfBounds);
        assert!(structure_type >= 1 && structure_type <= 4, EInvalidTerrain);

        let sender = tx_context::sender(ctx);
        assert!(ai_agent::get_owner(agent) == sender, EAgentNotOwned);

        let coord = coords_to_index(x, y);
        let territory = table::borrow_mut(&mut world.territories, coord);

        assert!(territory.is_claimed && territory.owner == sender, ENotTerritoryOwner);
        assert!(territory.structure == 0, EInvalidTerrain); // No existing structure

        // Structure costs (wood, stone, iron, crystal)
        let (wood_cost, stone_cost, iron_cost, crystal_cost) = structure_costs(structure_type);

        // Check and deduct resources from agent
        assert!(ai_agent::has_resources(agent, RESOURCE_WOOD, wood_cost), ENoResourcesToHarvest);
        assert!(ai_agent::has_resources(agent, RESOURCE_STONE, stone_cost), ENoResourcesToHarvest);
        assert!(ai_agent::has_resources(agent, RESOURCE_IRON, iron_cost), ENoResourcesToHarvest);
        assert!(ai_agent::has_resources(agent, RESOURCE_CRYSTAL, crystal_cost), ENoResourcesToHarvest);

        ai_agent::remove_resource(agent, RESOURCE_WOOD, wood_cost);
        ai_agent::remove_resource(agent, RESOURCE_STONE, stone_cost);
        ai_agent::remove_resource(agent, RESOURCE_IRON, iron_cost);
        ai_agent::remove_resource(agent, RESOURCE_CRYSTAL, crystal_cost);

        // Build structure
        territory.structure = structure_type;
        territory.structure_level = 1;
        territory.defense_rating = territory.defense_rating + structure_defense(structure_type, 1);

        event::emit(StructureBuilt {
            world_id: object::id(world),
            owner: sender,
            x,
            y,
            structure_type,
            level: 1,
        });
    }

    /// Upgrade an existing structure
    entry fun upgrade_structure(
        world: &mut AIWorld,
        agent: &mut AIAgent,
        x: u64,
        y: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(validate_coords(x, y), EOutOfBounds);

        let sender = tx_context::sender(ctx);
        assert!(ai_agent::get_owner(agent) == sender, EAgentNotOwned);

        let coord = coords_to_index(x, y);
        let territory = table::borrow_mut(&mut world.territories, coord);

        assert!(territory.is_claimed && territory.owner == sender, ENotTerritoryOwner);
        assert!(territory.structure > 0, EInvalidTerrain);
        assert!(territory.structure_level < 5, EInvalidTerrain); // Max level 5

        let new_level = territory.structure_level + 1;
        let (wood_cost, stone_cost, iron_cost, crystal_cost) = structure_upgrade_costs(
            territory.structure, new_level
        );

        assert!(ai_agent::has_resources(agent, RESOURCE_WOOD, wood_cost), ENoResourcesToHarvest);
        assert!(ai_agent::has_resources(agent, RESOURCE_STONE, stone_cost), ENoResourcesToHarvest);
        assert!(ai_agent::has_resources(agent, RESOURCE_IRON, iron_cost), ENoResourcesToHarvest);
        assert!(ai_agent::has_resources(agent, RESOURCE_CRYSTAL, crystal_cost), ENoResourcesToHarvest);

        ai_agent::remove_resource(agent, RESOURCE_WOOD, wood_cost);
        ai_agent::remove_resource(agent, RESOURCE_STONE, stone_cost);
        ai_agent::remove_resource(agent, RESOURCE_IRON, iron_cost);
        ai_agent::remove_resource(agent, RESOURCE_CRYSTAL, crystal_cost);

        let old_defense = structure_defense(territory.structure, territory.structure_level);
        territory.structure_level = new_level;
        let new_defense = structure_defense(territory.structure, new_level);
        territory.defense_rating = territory.defense_rating - old_defense + new_defense;

        event::emit(StructureUpgraded {
            world_id: object::id(world),
            owner: sender,
            x,
            y,
            structure_type: territory.structure,
            new_level,
        });
    }

    /// Get structure costs (wood, stone, iron, crystal)
    fun structure_costs(structure_type: u8): (u64, u64, u64, u64) {
        if (structure_type == 1) (20, 10, 5, 0)       // Outpost
        else if (structure_type == 2) (15, 20, 10, 5)  // Lab
        else if (structure_type == 3) (10, 30, 25, 0)  // Fortress
        else if (structure_type == 4) (25, 15, 15, 10) // Data Center
        else (0, 0, 0, 0)
    }

    /// Get structure upgrade costs for a given level
    fun structure_upgrade_costs(structure_type: u8, level: u8): (u64, u64, u64, u64) {
        let (base_wood, base_stone, base_iron, base_crystal) = structure_costs(structure_type);
        let multiplier = (level as u64);
        (
            base_wood * multiplier,
            base_stone * multiplier,
            base_iron * multiplier,
            base_crystal * multiplier
        )
    }

    /// Get structure defense bonus
    fun structure_defense(structure_type: u8, level: u8): u64 {
        let base = if (structure_type == 1) 10       // Outpost
        else if (structure_type == 2) 5              // Lab
        else if (structure_type == 3) 25             // Fortress
        else if (structure_type == 4) 15             // Data Center
        else 0;
        base * (level as u64)
    }

    // === Exploration ===

    /// Explore surrounding territories (reveals resources without claiming)
    entry fun explore_area(
        world: &mut AIWorld,
        agent: &mut AIAgent,
        direction: u8, // 0=north, 1=east, 2=south, 3=west
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(ai_agent::get_owner(agent) == sender, EAgentNotOwned);

        let agent_id = ai_agent::get_id(agent);
        assert!(table::contains(&world.agent_locations, agent_id), EAgentNotInTerritory);

        // Check exploration cooldown
        let current_time = clock::timestamp_ms(clock);
        assert!(
            current_time >= ai_agent::get_last_explore(agent) + EXPLORATION_COOLDOWN_MS,
            EExplorationCooldown
        );

        let coord = *table::borrow(&world.agent_locations, agent_id);
        let (cur_x, cur_y) = index_to_coords(coord);

        // Calculate target coordinates based on direction
        let (target_x, target_y) = if (direction == 0 && cur_y > 0) (cur_x, cur_y - 1) // North
        else if (direction == 1 && cur_x < WORLD_WIDTH - 1) (cur_x + 1, cur_y) // East
        else if (direction == 2 && cur_y < WORLD_HEIGHT - 1) (cur_x, cur_y + 1) // South
        else if (direction == 3 && cur_x > 0) (cur_x - 1, cur_y) // West
        else (cur_x, cur_y); // Invalid direction, stay in place

        let target_coord = coords_to_index(target_x, target_y);
        let target_territory = table::borrow(&world.territories, target_coord);

        // Update agent exploration timestamp
        ai_agent::set_last_explore(agent, current_time);

        // Grant small exploration bonus (random resource based on terrain)
        let bonus_amount = ai_agent::get_exploration_bonus(agent);
        if (bonus_amount > 0 && target_territory.resource_type != RESOURCE_NONE) {
            ai_agent::add_resource(agent, target_territory.resource_type, bonus_amount);
        };

        event::emit(TerritoryExplored {
            world_id: object::id(world),
            agent_id,
            x: target_x,
            y: target_y,
            terrain: target_territory.terrain,
            resource_type: target_territory.resource_type,
            resource_amount: target_territory.resource_amount,
        });
    }

    // === World Season ===

    /// Advance world season (admin function - resets resources, triggers events)
    entry fun advance_season(
        world: &mut AIWorld,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        world.current_season = world.current_season + 1;

        // Regenerate all resources fully
        let total = WORLD_WIDTH * WORLD_HEIGHT;
        let mut i = 0;
        while (i < total) {
            if (table::contains(&world.territories, i)) {
                let territory = table::borrow_mut(&mut world.territories, i);
                territory.resource_amount = territory.max_resources;
            };
            i = i + 1;
        };

        event::emit(WorldSeasonAdvanced {
            world_id: object::id(world),
            new_season: world.current_season,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // === View Functions ===

    /// Get world info
    public fun get_world_info(world: &AIWorld): (u64, u64, u64, u64, u64) {
        (
            world.width,
            world.height,
            world.total_territories_claimed,
            world.total_agents_created,
            world.current_season
        )
    }

    /// Get territory info at coordinates
    public fun get_territory(world: &AIWorld, x: u64, y: u64): (u8, u8, u64, bool, address, u8, u8) {
        assert!(validate_coords(x, y), EOutOfBounds);
        let coord = coords_to_index(x, y);
        let t = table::borrow(&world.territories, coord);
        (
            t.terrain,
            t.resource_type,
            t.resource_amount,
            t.is_claimed,
            t.owner,
            t.structure,
            t.structure_level
        )
    }

    /// Get territory defense rating
    public fun get_territory_defense(world: &AIWorld, x: u64, y: u64): u64 {
        assert!(validate_coords(x, y), EOutOfBounds);
        let coord = coords_to_index(x, y);
        let t = table::borrow(&world.territories, coord);
        t.defense_rating
    }

    /// Get agent location
    public fun get_agent_location(world: &AIWorld, agent_id: ID): (u64, u64) {
        assert!(table::contains(&world.agent_locations, agent_id), EAgentNotInTerritory);
        let coord = *table::borrow(&world.agent_locations, agent_id);
        index_to_coords(coord)
    }

    /// Check if agent is deployed
    public fun is_agent_deployed(world: &AIWorld, agent_id: ID): bool {
        table::contains(&world.agent_locations, agent_id)
    }

    /// Get total resources harvested
    public fun get_total_resources_harvested(world: &AIWorld): u64 {
        world.total_resources_harvested
    }

    // === Constants Getters ===
    public fun world_width(): u64 { WORLD_WIDTH }
    public fun world_height(): u64 { WORLD_HEIGHT }
    public fun terrain_plains(): u8 { TERRAIN_PLAINS }
    public fun terrain_forest(): u8 { TERRAIN_FOREST }
    public fun terrain_mountain(): u8 { TERRAIN_MOUNTAIN }
    public fun terrain_water(): u8 { TERRAIN_WATER }
    public fun terrain_desert(): u8 { TERRAIN_DESERT }
    public fun terrain_crystal_cave(): u8 { TERRAIN_CRYSTAL_CAVE }
    public fun resource_wood(): u8 { RESOURCE_WOOD }
    public fun resource_stone(): u8 { RESOURCE_STONE }
    public fun resource_iron(): u8 { RESOURCE_IRON }
    public fun resource_crystal(): u8 { RESOURCE_CRYSTAL }
    public fun resource_energy(): u8 { RESOURCE_ENERGY }
    public fun resource_data_shard(): u8 { RESOURCE_DATA_SHARD }
}
