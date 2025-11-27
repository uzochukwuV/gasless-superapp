module game_onchain::battle_royale{

use one::object::{Self, UID, ID};
use one::transfer;
use one::tx_context::{Self, TxContext};
use one::coin::{Self, Coin};
use one::oct::OCT;
use one::clock::{Self, Clock};
use one::event;
use one::table::{Self, Table};
use one::balance::{Self, Balance};
use std::string::String;
use std::vector;

// === Constants ===
const MAX_PLAYERS_PER_GAME: u64 = 50;
const MIN_PLAYERS_TO_START: u64 = 10;
const MAX_ROUNDS: u64 = 3;
const MIN_SURVIVORS_TO_CONTINUE: u64 = 3;
const QUESTION_TIME_MS: u64 = 120_000; // 2 minutes
const ANSWER_TIME_MS: u64 = 60_000; // 1 minute
const PLATFORM_FEE_BPS: u64 = 500; // 5%
const MAX_REVOTES_PER_GAME: u64 = 1;

// Character limits
const MAX_QUESTION_LENGTH: u64 = 50;
const MAX_OPTION_LENGTH: u64 = 50;

// Entry fees by tier (in MIST: 1 OCT = 1_000_000_000 MIST)
const TIER_1_FEE: u64 = 10_000_000; // 0.01 OCT
const TIER_2_FEE: u64 = 100_000_000; // 0.1 OCT
const TIER_3_FEE: u64 = 1_000_000_000; // 1 OCT
const TIER_4_FEE: u64 = 10_000_000_000; // 10 OCT
const TIER_5_FEE: u64 = 100_000_000_000; // 100 OCT

// Leaderboard base points by ending round
const ROUND_1_POINTS: u64 = 5;
const ROUND_2_POINTS: u64 = 3;
const ROUND_3_POINTS: u64 = 10;

// === Error Codes ===
const EInvalidTier: u64 = 0;
const EGameFull: u64 = 1;
const EGameNotWaiting: u64 = 2;
const ENotEnoughPlayers: u64 = 3;
const EGameNotActive: u64 = 4;
const ENotQuestioner: u64 = 5;
const ETimeNotExpired: u64 = 6;
const ETimeExpired: u64 = 7;
const EInvalidAnswer: u64 = 8;
const EAlreadyAnswered: u64 = 9;
const EPlayerEliminated: u64 = 10;
const EInsufficientPayment: u64 = 11;
const EGameNotFinished: u64 = 12;
const EPrizeAlreadyClaimed: u64 = 13;
const ENotSurvivor: u64 = 14;
const EQuestionTooLong: u64 = 15;
const EOptionTooLong: u64 = 16;
const EMaxRevotesReached: u64 = 17;
const ENoQuestionAsked: u64 = 18;
const EVotingStillActive: u64 = 19;

// === Structs ===

/// Platform treasury shared object
public struct PlatformTreasury has key {
    id: UID,
    balance: Balance<OCT>,
}

/// Tier lobby - one per tier
public struct TierLobby has key {
    id: UID,
    tier: u8,
    entry_fee: u64,
}

/// Game state
public struct Game has key {
    id: UID,
    tier: u8,
    entry_fee: u64,
    
    // Player tracking
    players: vector<address>,
    eliminated: vector<address>,
    player_answers: Table<address, u8>, // Current round answers (1/2/3)
    
    // Game state
    status: u8, // 0=waiting, 1=active, 2=finished, 3=cancelled
    current_round: u64,
    current_questioner: address,
    question_asked: bool,
    question_text: String,
    option_a: String,
    option_b: String,
    option_c: String,
    
    // Timing
    round_start_time: u64,
    deadline: u64,
    
    // Prize & revote
    prize_pool: Balance<OCT>,
    revote_count: u64,
    prize_claimed: Table<address, bool>,
}

/// Player ticket NFT (proof of participation + leaderboard points)
public struct PlayerTicket has key, store {
    id: UID,
    game_id: ID,
    player: address,
    tier: u8,
    points: u64,
    ending_round: u64,
    survived: bool,
}

// === Events ===

public struct TierLobbyCreated has copy, drop {
    lobby_id: ID,
    tier: u8,
    entry_fee: u64,
}

public struct GameCreated has copy, drop {
    game_id: ID,
    tier: u8,
    entry_fee: u64,
}

public struct PlayerJoined has copy, drop {
    game_id: ID,
    player: address,
    player_count: u64,
}

public struct GameStarted has copy, drop {
    game_id: ID,
    player_count: u64,
    first_questioner: address,
}

public struct RoundStarted has copy, drop {
    game_id: ID,
    round: u64,
    questioner: address,
    deadline: u64,
}

public struct QuestionAsked has copy, drop {
    game_id: ID,
    round: u64,
    questioner: address,
    question: String,
}

public struct AnswerSubmitted has copy, drop {
    game_id: ID,
    player: address,
    round: u64,
}

public struct RevoteTriggered has copy, drop {
    game_id: ID,
    round: u64,
    reason: String,
    new_questioner: address,
}

public struct RoundFinalized has copy, drop {
    game_id: ID,
    round: u64,
    eliminated_option: u8,
    eliminated_count: u64,
    survivors_count: u64,
}

public struct GameFinished has copy, drop {
    game_id: ID,
    ending_round: u64,
    survivors_count: u64,
    prize_per_survivor: u64,
}

public struct GameCancelled has copy, drop {
    game_id: ID,
    reason: String,
    prize_to_platform: u64,
}

public struct PrizeClaimed has copy, drop {
    game_id: ID,
    player: address,
    amount: u64,
}

public struct PlatformTreasuryCreated has copy, drop {
    treasury_id: ID,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    // Create platform treasury
    let treasury = PlatformTreasury {
        id: object::new(ctx),
        balance: balance::zero(),
    };

    event::emit(PlatformTreasuryCreated {
        treasury_id: object::id(&treasury),
    });

    transfer::share_object(treasury);

    // Create tier lobbies
    create_tier_lobby(1, TIER_1_FEE, ctx);
    create_tier_lobby(2, TIER_2_FEE, ctx);
    create_tier_lobby(3, TIER_3_FEE, ctx);
    create_tier_lobby(4, TIER_4_FEE, ctx);
    create_tier_lobby(5, TIER_5_FEE, ctx);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    // Create platform treasury
    let treasury = PlatformTreasury {
        id: object::new(ctx),
        balance: balance::zero(),
    };

    event::emit(PlatformTreasuryCreated {
        treasury_id: object::id(&treasury),
    });

    transfer::share_object(treasury);

    // Create only tier 1 lobby for testing
    create_tier_lobby(1, TIER_1_FEE, ctx);
}

fun create_tier_lobby(tier: u8, entry_fee: u64, ctx: &mut TxContext) {
    let lobby = TierLobby {
        id: object::new(ctx),
        tier,
        entry_fee,
    };
    
    event::emit(TierLobbyCreated {
        lobby_id: object::id(&lobby),
        tier,
        entry_fee,
    });
    
    transfer::share_object(lobby);
}

// === Game Creation ===

/// Create new game for a tier
public entry fun create_game(
    lobby: &TierLobby,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let game = Game {
        id: object::new(ctx),
        tier: lobby.tier,
        entry_fee: lobby.entry_fee,
        players: vector::empty(),
        eliminated: vector::empty(),
        player_answers: table::new(ctx),
        status: 0, // waiting
        current_round: 0,
        current_questioner: @0x0,
        question_asked: false,
        question_text: std::string::utf8(b""),
        option_a: std::string::utf8(b""),
        option_b: std::string::utf8(b""),
        option_c: std::string::utf8(b""),
        round_start_time: clock::timestamp_ms(clock),
        deadline: 0,
        prize_pool: balance::zero(),
        revote_count: 0,
        prize_claimed: table::new(ctx),
    };
    
    event::emit(GameCreated {
        game_id: object::id(&game),
        tier: lobby.tier,
        entry_fee: lobby.entry_fee,
    });
    
    transfer::share_object(game);
}

// === Join Game ===

/// Join existing game
public entry fun join_game(
    lobby: &TierLobby,
    game: &mut Game,
    treasury: &mut PlatformTreasury,
    mut payment: Coin<OCT>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(game.tier == lobby.tier, EInvalidTier);
    assert!(vector::length(&game.players) < MAX_PLAYERS_PER_GAME, EGameFull);
    assert!(game.status == 0, EGameNotWaiting);
    assert!(coin::value(&payment) >= lobby.entry_fee, EInsufficientPayment);
    
    let player = tx_context::sender(ctx);
    
    // Split platform fee (5%)
    let fee_amount = (lobby.entry_fee * PLATFORM_FEE_BPS) / 10000;
    let fee_coin = coin::split(&mut payment, fee_amount, ctx);
    balance::join(&mut treasury.balance, coin::into_balance(fee_coin));
    
    // Add to prize pool (95%)
    let prize_amount = lobby.entry_fee - fee_amount;
    let prize_coin = coin::split(&mut payment, prize_amount, ctx);
    balance::join(&mut game.prize_pool, coin::into_balance(prize_coin));
    
    // Add player
    vector::push_back(&mut game.players, player);
    
    event::emit(PlayerJoined {
        game_id: object::id(game),
        player,
        player_count: vector::length(&game.players),
    });
    
    // Auto-start at 50 players
    if (vector::length(&game.players) == MAX_PLAYERS_PER_GAME) {
        start_game_internal(game, clock, ctx);
    };
    
    // Return change to player
    transfer::public_transfer(payment, player);
}

// === Game Start ===

/// Manually start game (if 10-49 players)
public entry fun start_game(
    game: &mut Game,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(game.status == 0, EGameNotWaiting);
    assert!(
        vector::length(&game.players) >= MIN_PLAYERS_TO_START,
        ENotEnoughPlayers
    );
    
    start_game_internal(game, clock, ctx);
}

fun start_game_internal(
    game: &mut Game,
    clock: &Clock,
    ctx: &mut TxContext
) {
    game.status = 1; // active
    game.current_round = 1;
    
    // Select first questioner randomly
    let seed = clock::timestamp_ms(clock) + tx_context::epoch(ctx);
    let questioner_index = (seed % vector::length(&game.players));
    game.current_questioner = *vector::borrow(&game.players, questioner_index);
    
    game.round_start_time = clock::timestamp_ms(clock);
    game.deadline = game.round_start_time + QUESTION_TIME_MS;
    game.question_asked = false;
    
    event::emit(GameStarted {
        game_id: object::id(game),
        player_count: vector::length(&game.players),
        first_questioner: game.current_questioner,
    });
    
    event::emit(RoundStarted {
        game_id: object::id(game),
        round: game.current_round,
        questioner: game.current_questioner,
        deadline: game.deadline,
    });
}

// === Question Asking ===

/// Questioner asks question (or anyone if timeout)
public entry fun ask_question(
    game: &mut Game,
    question: String,
    option_a: String,
    option_b: String,
    option_c: String,
    questioner_answer: u8, // 1, 2, or 3
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(game.status == 1, EGameNotActive);
    assert!(!game.question_asked, ENoQuestionAsked);
    assert!(questioner_answer >= 1 && questioner_answer <= 3, EInvalidAnswer);
    
    let sender = tx_context::sender(ctx);
    let current_time = clock::timestamp_ms(clock);
    
    // Validate character limits
    assert!(
        std::string::length(&question) <= MAX_QUESTION_LENGTH,
        EQuestionTooLong
    );
    assert!(
        std::string::length(&option_a) <= MAX_OPTION_LENGTH,
        EOptionTooLong
    );
    assert!(
        std::string::length(&option_b) <= MAX_OPTION_LENGTH,
        EOptionTooLong
    );
    assert!(
        std::string::length(&option_c) <= MAX_OPTION_LENGTH,
        EOptionTooLong
    );
    
    // Check if original questioner or timeout (anyone can ask)
    if (sender != game.current_questioner) {
        assert!(current_time > game.deadline, ENotQuestioner);
        // Update questioner to whoever asked
        game.current_questioner = sender;
    } else {
        assert!(current_time <= game.deadline, ETimeExpired);
    };
    
    // Store question
    game.question_text = question;
    game.option_a = option_a;
    game.option_b = option_b;
    game.option_c = option_c;
    game.question_asked = true;
    
    // Questioner must answer their own question
    table::add(&mut game.player_answers, sender, questioner_answer);
    
    // Set answer deadline
    game.deadline = current_time + ANSWER_TIME_MS;
    
    event::emit(QuestionAsked {
        game_id: object::id(game),
        round: game.current_round,
        questioner: sender,
        question,
    });
    
    event::emit(AnswerSubmitted {
        game_id: object::id(game),
        player: sender,
        round: game.current_round,
    });
}

// === Answer Submission ===

/// Player submits answer
public entry fun submit_answer(
    game: &mut Game,
    choice: u8, // 1, 2, or 3
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(game.status == 1, EGameNotActive);
    assert!(game.question_asked, ENoQuestionAsked);
    assert!(choice >= 1 && choice <= 3, EInvalidAnswer);
    
    let sender = tx_context::sender(ctx);
    let current_time = clock::timestamp_ms(clock);
    
    // Check player is not eliminated
    assert!(!vector::contains(&game.eliminated, &sender), EPlayerEliminated);
    
    // Check within deadline
    assert!(current_time <= game.deadline, ETimeExpired);
    
    // Remove old answer if exists (from previous revote)
    if (table::contains(&game.player_answers, sender)) {
        table::remove(&mut game.player_answers, sender);
    };
    
    // Record new answer
    table::add(&mut game.player_answers, sender, choice);
    
    event::emit(AnswerSubmitted {
        game_id: object::id(game),
        player: sender,
        round: game.current_round,
    });
}

// === Round Finalization ===

/// Finalize round (anyone can call after deadline)
public entry fun finalize_round(
    game: &mut Game,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(game.status == 1, EGameNotActive);
    assert!(game.question_asked, ENoQuestionAsked);
    
    let current_time = clock::timestamp_ms(clock);
    assert!(current_time > game.deadline, ETimeNotExpired);
    
    // Count votes
    let (option_1_votes, option_2_votes, option_3_votes) = count_votes(game);
    
    // Find minority (option with LEAST votes)
    let min_votes = min_of_three(option_1_votes, option_2_votes, option_3_votes);
    
    // Check for tie in minority
    let mut tied_options = vector::empty<u8>();
    if (option_1_votes == min_votes) vector::push_back(&mut tied_options, 1);
    if (option_2_votes == min_votes) vector::push_back(&mut tied_options, 2);
    if (option_3_votes == min_votes) vector::push_back(&mut tied_options, 3);
    
    // If 2+ options tied for last place → REVOTE
    if (vector::length(&tied_options) > 1) {
        handle_revote(game, clock, ctx);
        return
    };
    
    // Single minority - eliminate those players
    let minority_option = *vector::borrow(&tied_options, 0);
    let eliminated_count = eliminate_minority(game, minority_option);
    
    event::emit(RoundFinalized {
        game_id: object::id(game),
        round: game.current_round,
        eliminated_option: minority_option,
        eliminated_count,
        survivors_count: vector::length(&game.players) - vector::length(&game.eliminated),
    });
    
    // Check if game should end
    let survivors_count = vector::length(&game.players) - vector::length(&game.eliminated);
    
    if (survivors_count < MIN_SURVIVORS_TO_CONTINUE || game.current_round >= MAX_ROUNDS) {
        finish_game(game, ctx);
    } else {
        // Start next round
        start_next_round(game, clock, ctx);
    }
}

fun count_votes(game: &Game): (u64, u64, u64) {
    let mut option_1 = 0u64;
    let mut option_2 = 0u64;
    let mut option_3 = 0u64;
    
    let players_len = vector::length(&game.players);
    let mut i = 0;
    
    while (i < players_len) {
        let player = vector::borrow(&game.players, i);
        
        // Only count if not eliminated
        if (!vector::contains(&game.eliminated, player)) {
            if (table::contains(&game.player_answers, *player)) {
                let choice = *table::borrow(&game.player_answers, *player);
                if (choice == 1) option_1 = option_1 + 1
                else if (choice == 2) option_2 = option_2 + 1
                else if (choice == 3) option_3 = option_3 + 1;
            }
            // else: didn't answer, will be auto-eliminated
        };
        
        i = i + 1;
    };
    
    (option_1, option_2, option_3)
}

fun min_of_three(a: u64, b: u64, c: u64): u64 {
    let mut min = a;
    if (b < min) min = b;
    if (c < min) min = c;
    min
}

fun eliminate_minority(game: &mut Game, minority_option: u8): u64 {
    let mut eliminated_count = 0u64;
    let players_len = vector::length(&game.players);
    let mut i = 0;
    
    while (i < players_len) {
        let player = vector::borrow(&game.players, i);
        
        // Skip if already eliminated
        if (!vector::contains(&game.eliminated, player)) {
            let mut should_eliminate = false;
            
            if (table::contains(&game.player_answers, *player)) {
                let choice = *table::borrow(&game.player_answers, *player);
                if (choice == minority_option) {
                    should_eliminate = true;
                }
            } else {
                // Didn't answer = auto-eliminate
                should_eliminate = true;
            };
            
            if (should_eliminate) {
                vector::push_back(&mut game.eliminated, *player);
                eliminated_count = eliminated_count + 1;
            }
        };
        
        i = i + 1;
    };
    
    eliminated_count
}

// === Revote Logic ===

fun handle_revote(
    game: &mut Game,
    clock: &Clock,
    ctx: &mut TxContext
) {
    game.revote_count = game.revote_count + 1;
    
    // If max revotes reached, cancel game and send prize to platform
    if (game.revote_count > MAX_REVOTES_PER_GAME) {
        cancel_game(game, std::string::utf8(b"Max revotes reached"), ctx);
        return
    };
    
    // Clear question data
    clear_round_data(game);
    
    // Select new random questioner from survivors
    let remaining = get_remaining_players(game);
    let seed = clock::timestamp_ms(clock) + tx_context::epoch(ctx);
    let index = seed % vector::length(&remaining);
    game.current_questioner = *vector::borrow(&remaining, index);
    
    game.round_start_time = clock::timestamp_ms(clock);
    game.deadline = game.round_start_time + QUESTION_TIME_MS;
    game.question_asked = false;
    
    event::emit(RevoteTriggered {
        game_id: object::id(game),
        round: game.current_round,
        reason: std::string::utf8(b"Tie for last place"),
        new_questioner: game.current_questioner,
    });
}

fun clear_round_data(game: &mut Game) {
    // Clear question text (answers will be overwritten on new submissions)
    game.question_text = std::string::utf8(b"");
    game.option_a = std::string::utf8(b"");
    game.option_b = std::string::utf8(b"");
    game.option_c = std::string::utf8(b"");
}

fun start_next_round(
    game: &mut Game,
    clock: &Clock,
    ctx: &mut TxContext
) {
    game.current_round = game.current_round + 1;
    
    // Clear previous round data
    clear_round_data(game);
    
    // Select new random questioner from survivors
    let remaining = get_remaining_players(game);
    let seed = clock::timestamp_ms(clock) + tx_context::epoch(ctx);
    let index = seed % vector::length(&remaining);
    game.current_questioner = *vector::borrow(&remaining, index);
    
    game.round_start_time = clock::timestamp_ms(clock);
    game.deadline = game.round_start_time + QUESTION_TIME_MS;
    game.question_asked = false;
    
    event::emit(RoundStarted {
        game_id: object::id(game),
        round: game.current_round,
        questioner: game.current_questioner,
        deadline: game.deadline,
    });
}

fun get_remaining_players(game: &Game): vector<address> {
    let mut remaining = vector::empty<address>();
    let players_len = vector::length(&game.players);
    let mut i = 0;
    
    while (i < players_len) {
        let player = vector::borrow(&game.players, i);
        if (!vector::contains(&game.eliminated, player)) {
            vector::push_back(&mut remaining, *player);
        };
        i = i + 1;
    };
    
    remaining
}

// === Game End ===

fun finish_game(game: &mut Game, ctx: &mut TxContext) {
    game.status = 2; // finished
    
    let survivors = get_remaining_players(game);
    let survivors_count = vector::length(&survivors);
    let total_prize = balance::value(&game.prize_pool);
    
    let prize_per_survivor = if (survivors_count > 0) {
        total_prize / survivors_count
    } else {
        0
    };
    
    event::emit(GameFinished {
        game_id: object::id(game),
        ending_round: game.current_round,
        survivors_count,
        prize_per_survivor,
    });
    
    // Mint PlayerTicket NFTs for all players
    mint_player_tickets(game, &survivors, ctx);
}

fun cancel_game(game: &mut Game, reason: String, ctx: &mut TxContext) {
    game.status = 3; // cancelled
    
    let prize_amount = balance::value(&game.prize_pool);
    
    event::emit(GameCancelled {
        game_id: object::id(game),
        reason,
        prize_to_platform: prize_amount,
    });
    
    // Mint 0-point tickets for participants
    let empty_survivors = vector::empty<address>();
    mint_player_tickets(game, &empty_survivors, ctx);
}

fun mint_player_tickets(
    game: &Game,
    survivors: &vector<address>,
    ctx: &mut TxContext
) {
    let players_len = vector::length(&game.players);
    let mut i = 0;
    
    while (i < players_len) {
        let player = vector::borrow(&game.players, i);
        let survived = vector::contains(survivors, player);
        
        let points = if (survived) {
            calculate_points(game.tier, game.current_round)
        } else {
            0
        };
        
        let ticket = PlayerTicket {
            id: object::new(ctx),
            game_id: object::id(game),
            player: *player,
            tier: game.tier,
            points,
            ending_round: game.current_round,
            survived,
        };
        
        transfer::transfer(ticket, *player);
        
        i = i + 1;
    }
}

fun calculate_points(tier: u8, ending_round: u64): u64 {
    let base_points = if (ending_round == 1) ROUND_1_POINTS
        else if (ending_round == 2) ROUND_2_POINTS
        else ROUND_3_POINTS;
    
    base_points * (tier as u64)
}

// === Prize Claiming ===

/// Survivors claim their share of prize
public entry fun claim_prize(
    game: &mut Game,
    ctx: &mut TxContext
) {
    assert!(game.status == 2, EGameNotFinished);
    
    let sender = tx_context::sender(ctx);
    
    // Check is survivor
    let survivors = get_remaining_players(game);
    assert!(vector::contains(&survivors, &sender), ENotSurvivor);
    
    // Check hasn't claimed yet
    assert!(!table::contains(&game.prize_claimed, sender), EPrizeAlreadyClaimed);
    
    // Calculate share
    let survivors_count = vector::length(&survivors);
    let total_prize = balance::value(&game.prize_pool);
    let prize_share = total_prize / survivors_count;
    
    // Mark as claimed
    table::add(&mut game.prize_claimed, sender, true);
    
    // Transfer prize
    let prize_coin = coin::from_balance(
        balance::split(&mut game.prize_pool, prize_share),
        ctx
    );
    
    transfer::public_transfer(prize_coin, sender);
    
    event::emit(PrizeClaimed {
        game_id: object::id(game),
        player: sender,
        amount: prize_share,
    });
}

// === Admin Functions ===

/// Withdraw platform treasury
public entry fun withdraw_platform_fees(
    treasury: &mut PlatformTreasury,
    ctx: &mut TxContext
) {
    // TODO: Add admin access control
    let amount = balance::value(&treasury.balance);
    
    if (amount > 0) {
        let coin = coin::from_balance(
            balance::withdraw_all(&mut treasury.balance),
            ctx
        );
        
        transfer::public_transfer(coin, tx_context::sender(ctx));
    }
}

/// Withdraw cancelled game funds to platform
public entry fun withdraw_cancelled_game_funds(
    game: &mut Game,
    treasury: &mut PlatformTreasury,
    _ctx: &mut TxContext
) {
    assert!(game.status == 3, EGameNotFinished);
    
    let amount = balance::value(&game.prize_pool);
    
    if (amount > 0) {
        balance::join(
            &mut treasury.balance,
            balance::withdraw_all(&mut game.prize_pool)
        );
    }
}

// === View Functions ===

public fun get_game_info(game: &Game): (u8, u8, u64, u64, u64, u64, address, bool) {
    (
        game.tier,
        game.status,
        game.current_round,
        vector::length(&game.players),
        vector::length(&game.eliminated),
        balance::value(&game.prize_pool),
        game.current_questioner,
        game.question_asked
    )
}

public fun get_survivors(game: &Game): vector<address> {
    get_remaining_players(game)
}

public fun get_player_ticket_info(ticket: &PlayerTicket): (ID, address, u8, u64, u64, bool) {
    (
        ticket.game_id,
        ticket.player,
        ticket.tier,
        ticket.points,
        ticket.ending_round,
        ticket.survived
    )
}

public fun get_lobby_info(lobby: &TierLobby): (u8, u64) {
    (lobby.tier, lobby.entry_fee)
}

// === Additional View Functions for Frontend ===

/// Check if a player is in the game
public fun is_player_in_game(game: &Game, player: address): bool {
    vector::contains(&game.players, &player)
}

/// Check if a player is eliminated
public fun is_player_eliminated(game: &Game, player: address): bool {
    vector::contains(&game.eliminated, &player)
}

/// Get current question details
public fun get_current_question(game: &Game): (String, String, String, String) {
    (game.question_text, game.option_a, game.option_b, game.option_c)
}

/// Check if player has answered current round
public fun has_player_answered(game: &Game, player: address): bool {
    table::contains(&game.player_answers, player)
}

/// Get player's answer for current round (if they answered)
public fun get_player_answer(game: &Game, player: address): u8 {
    *table::borrow(&game.player_answers, player)
}

/// Get time remaining for current phase (in milliseconds)
public fun get_time_remaining(game: &Game, clock: &Clock): u64 {
    let current_time = clock::timestamp_ms(clock);
    if (current_time >= game.deadline) {
        0
    } else {
        game.deadline - current_time
    }
}

/// Get total number of players who have voted (safe to show during voting)
public fun get_answer_count(game: &Game): u64 {
    let mut count = 0;
    let mut i = 0;
    let len = vector::length(&game.players);

    while (i < len) {
        let player = vector::borrow(&game.players, i);
        if (table::contains(&game.player_answers, *player)) {
            count = count + 1;
        };
        i = i + 1;
    };

    count
}

/// Get voting statistics for current round (only available after deadline)
public fun get_voting_stats(game: &Game, clock: &Clock): (u64, u64, u64) {
    // Voting results should only be visible after the round deadline
    let current_time = clock::timestamp_ms(clock);
    assert!(current_time >= game.deadline, EVotingStillActive);

    let mut count_a = 0;
    let mut count_b = 0;
    let mut count_c = 0;

    let mut i = 0;
    let len = vector::length(&game.players);
    while (i < len) {
        let player = vector::borrow(&game.players, i);
        if (table::contains(&game.player_answers, *player)) {
            let answer = *table::borrow(&game.player_answers, *player);
            if (answer == 1) count_a = count_a + 1
            else if (answer == 2) count_b = count_b + 1
            else if (answer == 3) count_c = count_c + 1;
        };
        i = i + 1;
    };

    (count_a, count_b, count_c)
}

/// Check if player can claim prize
public fun can_claim_prize(game: &Game, player: address): bool {
    game.status == 2 && // finished
    !vector::contains(&game.eliminated, &player) &&
    !table::contains(&game.prize_claimed, player)
}
}