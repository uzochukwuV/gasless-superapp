/// Sports Match Game Engine
/// Dynamic single-match creation with native One Chain randomness
module leaguealpha::game_engine {
    use one::object::{Self, UID};
    use one::transfer;
    use one::tx_context::{Self, TxContext};
    use one::clock::{Self, Clock};
    use one::event;
    use one::random::{Self, Random, RandomGenerator};
    use std::string::{Self, String};

    // === Constants ===
    const TEAMS_COUNT: u64 = 20;

    // Match outcomes
    const OUTCOME_PENDING: u8 = 0;
    const OUTCOME_HOME_WIN: u8 = 1;
    const OUTCOME_AWAY_WIN: u8 = 2;
    const OUTCOME_DRAW: u8 = 3;

    // === Error Codes ===
    const E_NOT_ADMIN: u64 = 0;
    const E_INVALID_TEAM_ID: u64 = 1;
    const E_SAME_TEAM: u64 = 2;
    const E_DEADLINE_NOT_REACHED: u64 = 3;
    const E_ALREADY_SETTLED: u64 = 4;

    // === Structs ===

    /// Single match state
    public struct Match has store, copy, drop {
        match_id: u64,
        home_team_id: u64,
        away_team_id: u64,
        home_score: u8,
        away_score: u8,
        outcome: u8,
        settled: bool,
        start_time: u64,
        deadline: u64,
    }

    /// Global game state (singleton shared object)
    public struct GameState has key {
        id: UID,
        teams: vector<Team>,
        admin: address,
        next_match_id: u64,
    }

    /// Team statistics
    public struct Team has store, copy, drop {
        name: String,
    }

    // === Events ===

    public struct MatchCreated has copy, drop {
        match_id: u64,
        home_team_id: u64,
        away_team_id: u64,
        deadline: u64,
    }

    public struct MatchSettled has copy, drop {
        match_id: u64,
        home_team_id: u64,
        away_team_id: u64,
        home_score: u8,
        away_score: u8,
        outcome: u8,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let game_state = GameState {
            id: object::new(ctx),
            teams: initialize_teams(),
            admin: tx_context::sender(ctx),
            next_match_id: 1,
        };
        transfer::share_object(game_state);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    /// Initialize 20 teams with crypto-themed names
    fun initialize_teams(): vector<Team> {
        let mut teams = vector::empty<Team>();
        vector::push_back(&mut teams, create_team(b"Manchester Virtual"));
        vector::push_back(&mut teams, create_team(b"Liverpool Digital"));
        vector::push_back(&mut teams, create_team(b"Chelsea Crypto"));
        vector::push_back(&mut teams, create_team(b"Arsenal Web3"));
        vector::push_back(&mut teams, create_team(b"Tottenham Chain"));
        vector::push_back(&mut teams, create_team(b"Manchester Block"));
        vector::push_back(&mut teams, create_team(b"Newcastle Node"));
        vector::push_back(&mut teams, create_team(b"Brighton Token"));
        vector::push_back(&mut teams, create_team(b"Aston Meta"));
        vector::push_back(&mut teams, create_team(b"West Ham Hash"));
        vector::push_back(&mut teams, create_team(b"Everton Ether"));
        vector::push_back(&mut teams, create_team(b"Leicester Link"));
        vector::push_back(&mut teams, create_team(b"Wolves Wallet"));
        vector::push_back(&mut teams, create_team(b"Crystal Palace Protocol"));
        vector::push_back(&mut teams, create_team(b"Fulham Fork"));
        vector::push_back(&mut teams, create_team(b"Brentford Bridge"));
        vector::push_back(&mut teams, create_team(b"Bournemouth Bytes"));
        vector::push_back(&mut teams, create_team(b"Nottingham NFT"));
        vector::push_back(&mut teams, create_team(b"Southampton Smart"));
        vector::push_back(&mut teams, create_team(b"Leeds Ledger"));
        teams
    }

    fun create_team(name: vector<u8>): Team {
        Team { name: string::utf8(name) }
    }

    // === Match Creation ===

    /// Create a new match with specified teams and deadline duration
    public entry fun create_match(
        game_state: &mut GameState,
        home_team_id: u64,
        away_team_id: u64,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == game_state.admin, E_NOT_ADMIN);
        assert!(home_team_id < TEAMS_COUNT, E_INVALID_TEAM_ID);
        assert!(away_team_id < TEAMS_COUNT, E_INVALID_TEAM_ID);
        assert!(home_team_id != away_team_id, E_SAME_TEAM);

        let match_id = game_state.next_match_id;
        game_state.next_match_id = match_id + 1;

        let current_time = clock::timestamp_ms(clock);

        let match_data = Match {
            match_id,
            home_team_id,
            away_team_id,
            home_score: 0,
            away_score: 0,
            outcome: OUTCOME_PENDING,
            settled: false,
            start_time: current_time,
            deadline: current_time + duration_ms,
        };

        event::emit(MatchCreated {
            match_id,
            home_team_id,
            away_team_id,
            deadline: match_data.deadline,
        });

        // Transfer match data as a copy (since Match has copy+drop)
        transfer::public_transfer(
            MatchData { id: object::new(ctx), match_data },
            tx_context::sender(ctx),
        );
    }

    /// Owned wrapper for match data (transferable object)
    public struct MatchData has key, store {
        id: UID,
        match_data: Match,
    }

    // === Match Settlement ===

    /// Settle match using One Chain native randomness
    /// Anyone can call after deadline
    #[allow(lint(public_random))]
    public entry fun settle_match(
        match_data: &mut MatchData,
        random_obj: &Random,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        assert!(!match_data.match_data.settled, E_ALREADY_SETTLED);
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= match_data.match_data.deadline, E_DEADLINE_NOT_REACHED);

        let mut generator = random::new_generator(random_obj, _ctx);

        let home_score = score_from_random(&mut generator);
        let away_score = score_from_random(&mut generator);

        match_data.match_data.home_score = home_score;
        match_data.match_data.away_score = away_score;
        match_data.match_data.settled = true;

        if (home_score > away_score) {
            match_data.match_data.outcome = OUTCOME_HOME_WIN;
        } else if (away_score > home_score) {
            match_data.match_data.outcome = OUTCOME_AWAY_WIN;
        } else {
            match_data.match_data.outcome = OUTCOME_DRAW;
        };

        event::emit(MatchSettled {
            match_id: match_data.match_data.match_id,
            home_team_id: match_data.match_data.home_team_id,
            away_team_id: match_data.match_data.away_team_id,
            home_score,
            away_score,
            outcome: match_data.match_data.outcome,
        });
    }

    // === Randomness ===

    /// Convert random number to realistic football score (0-5)
    /// Distribution: 0=15%, 1=25%, 2=25%, 3=17%, 4=11%, 5=7%
    fun score_from_random(generator: &mut RandomGenerator): u8 {
        let roll = random::generate_u64_in_range(generator, 0, 99);
        if (roll < 15) { 0 }
        else if (roll < 40) { 1 }
        else if (roll < 65) { 2 }
        else if (roll < 82) { 3 }
        else if (roll < 93) { 4 }
        else { 5 }
    }

    // === View Functions ===

    public fun get_match_outcome(match_data: &MatchData): u8 {
        match_data.match_data.outcome
    }

    public fun is_match_settled(match_data: &MatchData): bool {
        match_data.match_data.settled
    }

    public fun get_match_id(match_data: &MatchData): u64 {
        match_data.match_data.match_id
    }

    public fun get_match_deadline(match_data: &MatchData): u64 {
        match_data.match_data.deadline
    }

    public fun get_match_teams(match_data: &MatchData): (u64, u64) {
        (match_data.match_data.home_team_id, match_data.match_data.away_team_id)
    }

    public fun get_match_score(match_data: &MatchData): (u8, u8) {
        (match_data.match_data.home_score, match_data.match_data.away_score)
    }

    public fun get_match_struct(match_data: &MatchData): &Match {
        &match_data.match_data
    }

    public fun teams_count(): u64 {
        TEAMS_COUNT
    }
}
