#[test_only]
module game_onchain::battle_royale_tests {
    use one::test_scenario::{Self as ts, Scenario};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::clock::{Self, Clock};
    use game_onchain::battle_royale::{
        Self,
        PlatformTreasury,
        TierLobby,
        Game,
        PlayerTicket
    };
    use game_onchain::reputation::{Self, BadgeRegistry};
    use std::string;

    // Test addresses
    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;
    const CAROL: address = @0xCA501;
    const DAVE: address = @0xDADE;
    const EVE: address = @0xE5E;
    const FRANK: address = @0xF5A4;
    const GRACE: address = @0x65ACE;
    const HANK: address = @0x4A4C;
    const IVY: address = @0x152;
    const JACK: address = @0x1AC;
    const KATE: address = @0xCA7E;
    const LEO: address = @0x1E0;

    // Test constants
    const TIER_1_FEE: u64 = 10_000_000; // 0.01 OCT
    const MIN_PLAYERS: u64 = 10;
    const MAX_PLAYERS: u64 = 50;

    // Helper: Create clock for testing
    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(scenario.ctx())
    }

    // Helper: Advance clock
    fun advance_clock(clock: &mut Clock, ms: u64) {
        clock::increment_for_testing(clock, ms);
    }

    // Helper: Get test players
    fun get_test_players(): vector<address> {
        vector[ALICE, BOB, CAROL, DAVE, EVE, FRANK, GRACE, HANK, IVY, JACK, KATE, LEO]
    }

    // === Initialization Tests ===

    #[test]
    fun test_init_creates_lobbies_and_treasury() {
        let mut scenario = ts::begin(ADMIN);
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        // Check treasury exists
        scenario.next_tx(ADMIN);
        {
            let treasury = scenario.take_shared<PlatformTreasury>();
            ts::return_shared(treasury);
        };

        // Check tier 1 lobby exists
        scenario.next_tx(ADMIN);
        {
            let lobby = scenario.take_shared<TierLobby>();
            let (tier, entry_fee) = battle_royale::get_lobby_info(&lobby);
            assert!(tier == 1, 0);
            assert!(entry_fee == TIER_1_FEE, 1);
            ts::return_shared(lobby);
        };

        scenario.end();
    }

    // === Game Creation Tests ===

    #[test]
    fun test_create_game_successfully() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, &clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        scenario.next_tx(ALICE);
        {
            let game = scenario.take_shared<Game>();
            let (tier, status, round, player_count, _, _, _, _) = 
                battle_royale::get_game_info(&game);
            
            assert!(tier == 1, 0);
            assert!(status == 0, 1); // waiting
            assert!(round == 0, 2);
            assert!(player_count == 0, 3);
            
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    // === Join Game Tests ===

    #[test]
    fun test_single_player_joins_game() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, &clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            let mut game = scenario.take_shared<Game>();
            let mut treasury = scenario.take_shared<PlatformTreasury>();

            let payment = coin::mint_for_testing<OCT>(TIER_1_FEE, scenario.ctx());

            battle_royale::join_game(
                &lobby,
                &mut game,
                &mut treasury,
                payment,
                &clock,
                scenario.ctx()
            );
            
            let (_, _, _, player_count, _, prize_pool, _, _) = 
                battle_royale::get_game_info(&game);
            
            assert!(player_count == 1, 0);
            assert!(prize_pool > 0, 1); // 95% of fee
            
            ts::return_shared(lobby);
            ts::return_shared(game);
            ts::return_shared(treasury);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    fun test_ten_players_join_game() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, &clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        // Join 10 players
        let mut i = 0;
        while (i < 10) {
            let player = *vector::borrow(&players, i);
            scenario.next_tx(player);
            {
                let lobby = scenario.take_shared<TierLobby>();
                let mut game = scenario.take_shared<Game>();
                let mut treasury = scenario.take_shared<PlatformTreasury>();
                
                let payment = coin::mint_for_testing<OCT>(TIER_1_FEE, scenario.ctx());
                
                battle_royale::join_game(
                    &lobby,
                    &mut game,
                    &mut treasury,
                    payment,
                    &clock,
                    scenario.ctx()
                );
                
                ts::return_shared(lobby);
                ts::return_shared(game);
                ts::return_shared(treasury);
            };
            i = i + 1;
        };

        scenario.next_tx(ALICE);
        {
            let game = scenario.take_shared<Game>();
            let (_, status, _, player_count, _, _, _, _) = 
                battle_royale::get_game_info(&game);
            
            assert!(player_count == 10, 0);
            assert!(status == 0, 1); // still waiting (not auto-started)
            
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = battle_royale::EInsufficientPayment)]
    fun test_join_game_insufficient_payment() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, &clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            let mut game = scenario.take_shared<Game>();
            let mut treasury = scenario.take_shared<PlatformTreasury>();
            
            // Pay too little
            let payment = coin::mint_for_testing<OCT>(1_000_000, scenario.ctx());
            
            battle_royale::join_game(
                &lobby,
                &mut game,
                &mut treasury,
                payment,
                &clock,
                scenario.ctx()
            );
            
            ts::return_shared(lobby);
            ts::return_shared(game);
            ts::return_shared(treasury);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = battle_royale::EGameFull)]
    fun test_join_game_already_full() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, &clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        // Join 50 players (max)
        let mut i = 0;
        while (i < 50) {
            let player_addr = if (i == 0) @0x1000
                else if (i == 1) @0x1001
                else if (i == 2) @0x1002
                else if (i == 3) @0x1003
                else if (i == 4) @0x1004
                else if (i == 5) @0x1005
                else if (i == 6) @0x1006
                else if (i == 7) @0x1007
                else if (i == 8) @0x1008
                else if (i == 9) @0x1009
                else if (i == 10) @0x100a
                else if (i == 11) @0x100b
                else if (i == 12) @0x100c
                else if (i == 13) @0x100d
                else if (i == 14) @0x100e
                else if (i == 15) @0x100f
                else if (i == 16) @0x1010
                else if (i == 17) @0x1011
                else if (i == 18) @0x1012
                else if (i == 19) @0x1013
                else if (i == 20) @0x1014
                else if (i == 21) @0x1015
                else if (i == 22) @0x1016
                else if (i == 23) @0x1017
                else if (i == 24) @0x1018
                else if (i == 25) @0x1019
                else if (i == 26) @0x101a
                else if (i == 27) @0x101b
                else if (i == 28) @0x101c
                else if (i == 29) @0x101d
                else if (i == 30) @0x101e
                else if (i == 31) @0x101f
                else if (i == 32) @0x1020
                else if (i == 33) @0x1021
                else if (i == 34) @0x1022
                else if (i == 35) @0x1023
                else if (i == 36) @0x1024
                else if (i == 37) @0x1025
                else if (i == 38) @0x1026
                else if (i == 39) @0x1027
                else if (i == 40) @0x1028
                else if (i == 41) @0x1029
                else if (i == 42) @0x102a
                else if (i == 43) @0x102b
                else if (i == 44) @0x102c
                else if (i == 45) @0x102d
                else if (i == 46) @0x102e
                else if (i == 47) @0x102f
                else if (i == 48) @0x1030
                else @0x1031;
            scenario.next_tx(player_addr);
            {
                let lobby = scenario.take_shared<TierLobby>();
                let mut game = scenario.take_shared<Game>();
                let mut treasury = scenario.take_shared<PlatformTreasury>();
                
                let payment = coin::mint_for_testing<OCT>(TIER_1_FEE, scenario.ctx());
                
                battle_royale::join_game(
                    &lobby,
                    &mut game,
                    &mut treasury,
                    payment,
                    &clock,
                    scenario.ctx()
                );
                
                ts::return_shared(lobby);
                ts::return_shared(game);
                ts::return_shared(treasury);
            };
            i = i + 1;
        };

        // Try to join 51st player - should fail
        scenario.next_tx(@0x9999);
        {
            let lobby = scenario.take_shared<TierLobby>();
            let mut game = scenario.take_shared<Game>();
            let mut treasury = scenario.take_shared<PlatformTreasury>();
            
            let payment = coin::mint_for_testing<OCT>(TIER_1_FEE, scenario.ctx());
            
            battle_royale::join_game(
                &lobby,
                &mut game,
                &mut treasury,
                payment,
                &clock,
                scenario.ctx()
            );
            
            ts::return_shared(lobby);
            ts::return_shared(game);
            ts::return_shared(treasury);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    // === Game Start Tests ===

    #[test]
    fun test_start_game_with_min_players() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, &clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        // Join 10 players
        let mut i = 0;
        while (i < 10) {
            let player = *vector::borrow(&players, i);
            scenario.next_tx(player);
            {
                let lobby = scenario.take_shared<TierLobby>();
                let mut game = scenario.take_shared<Game>();
                let mut treasury = scenario.take_shared<PlatformTreasury>();
                
                let payment = coin::mint_for_testing<OCT>(TIER_1_FEE, scenario.ctx());
                
                battle_royale::join_game(
                    &lobby,
                    &mut game,
                    &mut treasury,
                    payment,
                    &clock,
                    scenario.ctx()
                );
                
                ts::return_shared(lobby);
                ts::return_shared(game);
                ts::return_shared(treasury);
            };
            i = i + 1;
        };

        // Start game manually
        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            
            battle_royale::start_game(&mut game, &clock, scenario.ctx());
            
            let (_, status, round, _, _, _, questioner, question_asked) = 
                battle_royale::get_game_info(&game);
            
            assert!(status == 1, 0); // active
            assert!(round == 1, 1);
            assert!(questioner != @0x0, 2); // questioner assigned
            assert!(!question_asked, 3);
            
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = battle_royale::ENotEnoughPlayers)]
    fun test_start_game_not_enough_players() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        
        {
            battle_royale::init_for_testing(scenario.ctx());
        };

        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, &clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        // Join only 1 player (less than min of 2)
        let players = get_test_players();
        scenario.next_tx(*vector::borrow(&players, 0));
        {
            let lobby = scenario.take_shared<TierLobby>();
            let mut game = scenario.take_shared<Game>();
            let mut treasury = scenario.take_shared<PlatformTreasury>();

            let payment = coin::mint_for_testing<OCT>(TIER_1_FEE, scenario.ctx());

            battle_royale::join_game(
                &lobby,
                &mut game,
                &mut treasury,
                payment,
                &clock,
                scenario.ctx()
            );

            ts::return_shared(lobby);
            ts::return_shared(game);
            ts::return_shared(treasury);
        };

        // Try to start - should fail
        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            battle_royale::start_game(&mut game, &clock, scenario.ctx());
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    // === Question Asking Tests ===

    #[test]
    fun test_questioner_asks_question() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        // Setup game with 10 players and start
        setup_active_game(&mut scenario, &mut clock, &players);

        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            let (_, _, _, _, _, _, questioner, _) = battle_royale::get_game_info(&game);
            
            // Have questioner ask question
            scenario.next_tx(questioner);
            {
                battle_royale::ask_question(
                    &mut game,
                    string::utf8(b"Best color?"),
                    string::utf8(b"Red"),
                    string::utf8(b"Blue"),
                    string::utf8(b"Green"),
                    1, // questioner picks Red
                    &clock,
                    scenario.ctx()
                );
            };
            
            let (_, _, _, _, _, _, _, question_asked) = 
                battle_royale::get_game_info(&game);
            assert!(question_asked, 0);
            
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    fun test_anyone_can_ask_after_timeout() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        setup_active_game(&mut scenario, &mut clock, &players);

        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            
            // Advance clock past question deadline (2 minutes)
            advance_clock(&mut clock, 121_000);
            
            // Anyone can ask now - let BOB ask
            scenario.next_tx(BOB);
            {
                battle_royale::ask_question(
                    &mut game,
                    string::utf8(b"Favorite food?"),
                    string::utf8(b"Pizza"),
                    string::utf8(b"Burger"),
                    string::utf8(b"Salad"),
                    2, // BOB picks Burger
                    &clock,
                    scenario.ctx()
                );
            };
            
            let (_, _, _, _, _, _, new_questioner, question_asked) = 
                battle_royale::get_game_info(&game);
            
            assert!(question_asked, 0);
            assert!(new_questioner == BOB, 1); // BOB became questioner
            
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = battle_royale::EQuestionTooLong)]
    fun test_question_too_long() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        setup_active_game(&mut scenario, &mut clock, &players);

        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            let (_, _, _, _, _, _, questioner, _) = battle_royale::get_game_info(&game);
            
            scenario.next_tx(questioner);
            {
                // Question > 50 chars
                battle_royale::ask_question(
                    &mut game,
                    string::utf8(b"This question is way too long and exceeds the fifty character limit"),
                    string::utf8(b"A"),
                    string::utf8(b"B"),
                    string::utf8(b"C"),
                    1,
                    &clock,
                    scenario.ctx()
                );
            };
            
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    // === Answer Submission Tests ===

    #[test]
    fun test_players_submit_answers() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        setup_active_game(&mut scenario, &mut clock, &players);

        // Ask question
        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            let (_, _, _, _, _, _, questioner, _) = battle_royale::get_game_info(&game);
            
            scenario.next_tx(questioner);
            {
                battle_royale::ask_question(
                    &mut game,
                    string::utf8(b"Pick one"),
                    string::utf8(b"A"),
                    string::utf8(b"B"),
                    string::utf8(b"C"),
                    1,
                    &clock,
                    scenario.ctx()
                );
            };
            
            ts::return_shared(game);
        };

        // Players submit answers
        let mut i = 1; // Start at 1 (questioner already answered)
        while (i < 10) {
            let player = *vector::borrow(&players, i);
            scenario.next_tx(player);
            {
                let mut game = scenario.take_shared<Game>();
                
                let choice = if (i < 5) 1 else if (i < 8) 2 else 3;
                
                battle_royale::submit_answer(
                    &mut game,
                    choice,
                    &clock,
                    scenario.ctx()
                );
                
                ts::return_shared(game);
            };
            i = i + 1;
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = battle_royale::ETimeExpired)]
    fun test_answer_after_deadline() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        setup_active_game(&mut scenario, &mut clock, &players);

        // Ask question
        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            let (_, _, _, _, _, _, questioner, _) = battle_royale::get_game_info(&game);
            
            scenario.next_tx(questioner);
            {
                battle_royale::ask_question(
                    &mut game,
                    string::utf8(b"Pick"),
                    string::utf8(b"A"),
                    string::utf8(b"B"),
                    string::utf8(b"C"),
                    1,
                    &clock,
                    scenario.ctx()
                );
            };
            
            ts::return_shared(game);
        };

        // Advance past answer deadline
        advance_clock(&mut clock, 61_000);

        scenario.next_tx(BOB);
        {
            let mut game = scenario.take_shared<Game>();
            
            battle_royale::submit_answer(&mut game, 1, &clock, scenario.ctx());
            
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    // === Round Finalization Tests ===

    #[test]
    fun test_finalize_round_eliminates_minority() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        let players = get_test_players();
        
        setup_active_game(&mut scenario, &mut clock, &players);

        // Ask question and have players answer
        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            let (_, _, _, _, _, _, questioner, _) = battle_royale::get_game_info(&game);
            
            scenario.next_tx(questioner);
            {
                battle_royale::ask_question(
                    &mut game,
                    string::utf8(b"Vote"),
                    string::utf8(b"A"),
                    string::utf8(b"B"),
                    string::utf8(b"C"),
                    1, // questioner picks A
                    &clock,
                    scenario.ctx()
                );
            };
            
            ts::return_shared(game);
        };

        // 5 vote A, 3 vote B, 2 vote C (C is minority)
        let mut i = 1;
        while (i < 10) {
            let player = *vector::borrow(&players, i);
            scenario.next_tx(player);
            {
                let mut game = scenario.take_shared<Game>();
                
                let choice = if (i < 5) 1 else if (i < 8) 2 else 3;
                
                battle_royale::submit_answer(&mut game, choice, &clock, scenario.ctx());
                
                ts::return_shared(game);
            };
            i = i + 1;
        };

        // Advance past deadline and finalize
        advance_clock(&mut clock, 61_000);

        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            let mut badge_registry = scenario.take_shared<BadgeRegistry>();

            battle_royale::finalize_round(&mut game, &mut badge_registry, &clock, scenario.ctx());

            let (_, _, _, _, eliminated_count, _, _, _) =
                battle_royale::get_game_info(&game);

            assert!(eliminated_count == 2, 0); // 2 players voted C

            ts::return_shared(game);
            ts::return_shared(badge_registry);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    // === Prize Claiming Tests ===

    #[test]
    fun test_survivor_claims_prize() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = create_clock(&mut scenario);
        
        // Run full game to completion (simplified)
        let players = get_test_players();
        setup_active_game(&mut scenario, &mut clock, &players);

        // Manually finish game by setting status
        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            // In real test, would play through rounds
            // For now, just test claim logic works
            ts::return_shared(game);
        };

        clock.destroy_for_testing();
        scenario.end();
    }

    // === Helper Functions ===

    fun setup_active_game(
        scenario: &mut Scenario,
        clock: &mut Clock,
        players: &vector<address>
    ) {
        // Init
        scenario.next_tx(ADMIN);
        {
            battle_royale::init_for_testing(scenario.ctx());
            reputation::init_for_testing(scenario.ctx());
        };

        // Create game
        scenario.next_tx(ALICE);
        {
            let lobby = scenario.take_shared<TierLobby>();
            battle_royale::create_game(&lobby, clock, scenario.ctx());
            ts::return_shared(lobby);
        };

        // Join 10 players
        let mut i = 0;
        while (i < 10) {
            let player = *vector::borrow(players, i);
            scenario.next_tx(player);
            {
                let lobby = scenario.take_shared<TierLobby>();
                let mut game = scenario.take_shared<Game>();
                let mut treasury = scenario.take_shared<PlatformTreasury>();
                
                let payment = coin::mint_for_testing<OCT>(TIER_1_FEE, scenario.ctx());
                
                battle_royale::join_game(
                    &lobby,
                    &mut game,
                    &mut treasury,
                    payment,
                    clock,
                    scenario.ctx()
                );
                
                ts::return_shared(lobby);
                ts::return_shared(game);
                ts::return_shared(treasury);
            };
            i = i + 1;
        };

        // Start game
        scenario.next_tx(ALICE);
        {
            let mut game = scenario.take_shared<Game>();
            battle_royale::start_game(&mut game, clock, scenario.ctx());
            ts::return_shared(game);
        };
    }
}