#[test_only]
module game_onchain::game_test {
    use one::test_scenario::{Self as ts, Scenario};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::clock::{Self, Clock};
    use game_onchain::battle_royale::{Self, Game, TierLobby, PlatformTreasury, PlayerTicket};
    use game_onchain::role_machine;
    use game_onchain::items::{Self, ItemShop, ImmunityToken};
    use game_onchain::reputation::{Self, BadgeRegistry, ReputationBadge};

    // Test addresses
    const ADMIN: address = @0xAD;
    const PLAYER1: address = @0x1;
    const PLAYER2: address = @0x2;
    const PLAYER3: address = @0x3;
    const PLAYER4: address = @0x4;
    const PLAYER5: address = @0x5;
    const PLAYER6: address = @0x6;
    const PLAYER7: address = @0x7;
    const PLAYER8: address = @0x8;
    const PLAYER9: address = @0x9;
    const PLAYER10: address = @0xA;

    // Test amounts (in MIST)
    const TIER_1_FEE: u64 = 10_000_000; // 0.01 OCT
    const BASE_IMMUNITY_PRICE: u64 = 100_000_000; // 0.1 OCT

    /// Helper: Create test clock
    fun create_clock(scenario: &mut Scenario): Clock {
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, 1000000);
        clock
    }

    /// Helper: Mint test OCT coins
    fun mint_oct(scenario: &mut Scenario, amount: u64): Coin<OCT> {
        coin::mint_for_testing<OCT>(amount, ts::ctx(scenario))
    }

    #[test]
    fun test_initialization() {
        let mut scenario = ts::begin(ADMIN);

        // Initialize contracts
        {
            battle_royale::init_for_testing(ts::ctx(&mut scenario));
            items::init_for_testing(ts::ctx(&mut scenario));
            reputation::init_for_testing(ts::ctx(&mut scenario));
        };

        // Check platform treasury created
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_shared<PlatformTreasury>(), 0);
        };

        // Check tier lobby created
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_shared<TierLobby>(), 1);
        };

        // Check item shop created
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_shared<ItemShop>(), 2);
        };

        // Check badge registry created
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_shared<BadgeRegistry>(), 3);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_create_and_join_game() {
        let mut scenario = ts::begin(ADMIN);
        battle_royale::init_for_testing(ts::ctx(&mut scenario));

        // Create game
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let lobby = ts::take_shared<TierLobby>(&scenario);
            let clock = create_clock(&mut scenario);

            battle_royale::create_game(
                &lobby,
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(lobby);
        };

        // Player 1 joins
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let lobby = ts::take_shared<TierLobby>(&scenario);
            let mut game = ts::take_shared<Game>(&scenario);
            let mut treasury = ts::take_shared<PlatformTreasury>(&scenario);
            let clock = create_clock(&mut scenario);
            let payment = mint_oct(&mut scenario, TIER_1_FEE);

            battle_royale::join_game(
                &lobby,
                &mut game,
                &mut treasury,
                payment,
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(lobby);
            ts::return_shared(game);
            ts::return_shared(treasury);
        };

        // Player 2 joins
        ts::next_tx(&mut scenario, PLAYER2);
        {
            let lobby = ts::take_shared<TierLobby>(&scenario);
            let mut game = ts::take_shared<Game>(&scenario);
            let mut treasury = ts::take_shared<PlatformTreasury>(&scenario);
            let clock = create_clock(&mut scenario);
            let payment = mint_oct(&mut scenario, TIER_1_FEE);

            battle_royale::join_game(
                &lobby,
                &mut game,
                &mut treasury,
                payment,
                &clock,
                ts::ctx(&mut scenario)
            );

            let (_, status, _, player_count, _, _, _, _) = battle_royale::get_game_info(&game);
            assert!(status == 0, 100); // Still waiting
            assert!(player_count == 2, 101);

            clock::destroy_for_testing(clock);
            ts::return_shared(lobby);
            ts::return_shared(game);
            ts::return_shared(treasury);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_start_game_and_roles() {
        let mut scenario = ts::begin(ADMIN);
        battle_royale::init_for_testing(ts::ctx(&mut scenario));

        // Create and join game with 2 players
        setup_game_with_players(&mut scenario, 2);

        // Start game
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            battle_royale::start_game(
                &mut game,
                &clock,
                ts::ctx(&mut scenario)
            );

            let (_, status, round, _, _, _, _, _) = battle_royale::get_game_info(&game);
            assert!(status == 1, 200); // Active
            assert!(round == 1, 201);

            // Check role distribution (2 players = no saboteurs for 2-player game)
            let (citizens, saboteurs) = battle_royale::get_role_distribution(&game);
            assert!(citizens == 2, 202);
            assert!(saboteurs == 0, 203);

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_buy_immunity_token() {
        let mut scenario = ts::begin(ADMIN);
        items::init_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut shop = ts::take_shared<ItemShop>(&scenario);
            let clock = create_clock(&mut scenario);
            let payment = mint_oct(&mut scenario, BASE_IMMUNITY_PRICE);

            items::buy_immunity_token(
                &mut shop,
                1, // tier 1
                payment,
                &clock,
                ts::ctx(&mut scenario)
            );

            let (base_price, _, total_sold) = items::get_shop_info(&shop);
            assert!(base_price == BASE_IMMUNITY_PRICE, 300);
            assert!(total_sold == 1, 301);

            clock::destroy_for_testing(clock);
            ts::return_shared(shop);
        };

        // Check player received token
        ts::next_tx(&mut scenario, PLAYER1);
        {
            assert!(ts::has_most_recent_for_address<ImmunityToken>(PLAYER1), 302);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_use_immunity_token() {
        let mut scenario = ts::begin(ADMIN);
        battle_royale::init_for_testing(ts::ctx(&mut scenario));
        items::init_for_testing(ts::ctx(&mut scenario));

        // Buy immunity token
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut shop = ts::take_shared<ItemShop>(&scenario);
            let clock = create_clock(&mut scenario);
            let payment = mint_oct(&mut scenario, BASE_IMMUNITY_PRICE);

            items::buy_immunity_token(
                &mut shop,
                1,
                payment,
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(shop);
        };

        // Create and start game
        setup_game_with_players(&mut scenario, 2);

        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            battle_royale::start_game(&mut game, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // Use immunity token
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let token = ts::take_from_address<ImmunityToken>(&scenario, PLAYER1);

            battle_royale::use_immunity_token(
                &mut game,
                token,
                ts::ctx(&mut scenario)
            );

            ts::return_shared(game);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_reputation_badge_minting() {
        let mut scenario = ts::begin(ADMIN);
        reputation::init_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = ts::take_shared<BadgeRegistry>(&scenario);

            // Mint badge for player1
            reputation::mint_badge(
                &mut registry,
                PLAYER1,
                10, // initial points
                true, // won
                true, // was citizen
                1000000, // timestamp
                ts::ctx(&mut scenario)
            );

            assert!(reputation::has_badge(&registry, PLAYER1), 400);

            ts::return_shared(registry);
        };

        // Check player received badge
        ts::next_tx(&mut scenario, PLAYER1);
        {
            assert!(ts::has_most_recent_for_address<ReputationBadge>(PLAYER1), 401);

            let badge = ts::take_from_address<ReputationBadge>(&scenario, PLAYER1);
            let (games_played, games_won, points, level) = reputation::get_badge_stats(&badge);

            assert!(games_played == 1, 402);
            assert!(games_won == 1, 403);
            assert!(points == 10, 404);
            assert!(level == reputation::level_diamond(), 405); // 100% win rate = diamond

            ts::return_to_address(PLAYER1, badge);
        };

        ts::end(scenario);
    }

    // Helper function to get player address by index
    fun get_player_address(index: u64): address {
        if (index == 0) PLAYER1
        else if (index == 1) PLAYER2
        else if (index == 2) PLAYER3
        else if (index == 3) PLAYER4
        else if (index == 4) PLAYER5
        else if (index == 5) PLAYER6
        else if (index == 6) PLAYER7
        else if (index == 7) PLAYER8
        else if (index == 8) PLAYER9
        else PLAYER10
    }

    // Helper function to setup a game with N players
    fun setup_game_with_players(scenario: &mut Scenario, player_count: u64) {
        // Create game
        ts::next_tx(scenario, PLAYER1);
        {
            let lobby = ts::take_shared<TierLobby>(scenario);
            let clock = create_clock(scenario);

            battle_royale::create_game(&lobby, &clock, ts::ctx(scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(lobby);
        };

        // Wait for game to be available in shared storage
        ts::next_tx(scenario, PLAYER1);

        // Join players
        let mut i = 0;
        while (i < player_count) {
            let player = get_player_address(i);

            ts::next_tx(scenario, player);
            {
                let lobby = ts::take_shared<TierLobby>(scenario);
                let mut game = ts::take_shared<Game>(scenario);
                let mut treasury = ts::take_shared<PlatformTreasury>(scenario);
                let clock = create_clock(scenario);
                let payment = mint_oct(scenario, TIER_1_FEE);

                battle_royale::join_game(
                    &lobby,
                    &mut game,
                    &mut treasury,
                    payment,
                    &clock,
                    ts::ctx(scenario)
                );

                clock::destroy_for_testing(clock);
                ts::return_shared(lobby);
                ts::return_shared(game);
                ts::return_shared(treasury);
            };

            i = i + 1;
        };
    }

    #[test]
    fun test_full_game_flow_2_players() {
        let mut scenario = ts::begin(ADMIN);
        battle_royale::init_for_testing(ts::ctx(&mut scenario));
        reputation::init_for_testing(ts::ctx(&mut scenario));

        // Setup game with 2 players
        setup_game_with_players(&mut scenario, 2);

        // Start game
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            battle_royale::start_game(&mut game, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // Questioner asks question
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            let question = std::string::utf8(b"Test?");
            let opt_a = std::string::utf8(b"A");
            let opt_b = std::string::utf8(b"B");
            let opt_c = std::string::utf8(b"C");

            battle_royale::ask_question(
                &mut game,
                question,
                opt_a,
                opt_b,
                opt_c,
                1, // questioner answers A
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // Player 2 submits answer
        ts::next_tx(&mut scenario, PLAYER2);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            battle_royale::submit_answer(
                &mut game,
                1, // also answers A
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // Finalize round (both voted same, game continues)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let mut badge_registry = ts::take_shared<BadgeRegistry>(&scenario);
            let mut clock = create_clock(&mut scenario);

            // Fast forward past deadline
            clock::increment_for_testing(&mut clock, 120_001);

            battle_royale::finalize_round(
                &mut game,
                &mut badge_registry,
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
            ts::return_shared(badge_registry);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_full_game_flow_10_players() {
        let mut scenario = ts::begin(ADMIN);
        battle_royale::init_for_testing(ts::ctx(&mut scenario));
        items::init_for_testing(ts::ctx(&mut scenario));
        reputation::init_for_testing(ts::ctx(&mut scenario));

        // Setup game with 10 players
        setup_game_with_players(&mut scenario, 10);

        // Start game
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            battle_royale::start_game(&mut game, &clock, ts::ctx(&mut scenario));

            // Verify game started and roles assigned
            let (_, status, round, player_count, _, _, _, _) = battle_royale::get_game_info(&game);
            assert!(status == 1, 1000); // Active
            assert!(round == 1, 1001);
            assert!(player_count == 10, 1002);

            // Check role distribution (10 players = 3 saboteurs, 7 citizens)
            let (citizens, saboteurs) = battle_royale::get_role_distribution(&game);
            assert!(citizens == 7, 1003);
            assert!(saboteurs == 3, 1004);

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // Get the questioner address
        ts::next_tx(&mut scenario, PLAYER1);
        let questioner = {
            let game = ts::take_shared<Game>(&scenario);
            let (_, _, _, _, _, _, q, _) = battle_royale::get_game_info(&game);
            ts::return_shared(game);
            q
        };

        // ===== ROUND 1 =====
        // Questioner asks question
        ts::next_tx(&mut scenario, questioner);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            let question = std::string::utf8(b"Vote for majority");
            let opt_a = std::string::utf8(b"Option A");
            let opt_b = std::string::utf8(b"Option B");
            let opt_c = std::string::utf8(b"Option C");

            battle_royale::ask_question(
                &mut game,
                question,
                opt_a,
                opt_b,
                opt_c,
                1, // questioner picks A
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // All other players vote (simulate mixed voting)
        // Strategy: Majority votes A, some vote B, PLAYER9 and PLAYER10 vote C (minority)
        // We need to skip the questioner since they already voted when asking
        let mut i = 0u64;
        while (i < 10) {
            let player = get_player_address(i);

            // Skip the questioner (already voted)
            if (player != questioner) {
                // Explicitly control votes:
                // - PLAYER9 and PLAYER10 vote C (will be minority)
                // - Most others vote A (majority)
                // - A few vote B (safe middle ground)
                let vote = if (player == PLAYER9 || player == PLAYER10) {
                    3  // These two vote C (minority)
                } else if (i < 6) {
                    1  // First 6 vote A (majority)
                } else {
                    2  // Middle players vote B
                };

                ts::next_tx(&mut scenario, player);
                {
                    let mut game = ts::take_shared<Game>(&scenario);
                    let clock = create_clock(&mut scenario);

                    battle_royale::submit_answer(&mut game, vote, &clock, ts::ctx(&mut scenario));

                    clock::destroy_for_testing(clock);
                    ts::return_shared(game);
                };
            };

            i = i + 1;
        };

        // Player 9 buys and uses immunity token before finalization
        ts::next_tx(&mut scenario, PLAYER9);
        {
            let mut shop = ts::take_shared<ItemShop>(&scenario);
            let clock = create_clock(&mut scenario);
            let payment = mint_oct(&mut scenario, BASE_IMMUNITY_PRICE);

            items::buy_immunity_token(&mut shop, 1, payment, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(shop);
        };

        ts::next_tx(&mut scenario, PLAYER9);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let token = ts::take_from_address<ImmunityToken>(&scenario, PLAYER9);

            battle_royale::use_immunity_token(&mut game, token, ts::ctx(&mut scenario));

            // Verify immunity is active
            assert!(battle_royale::has_used_immunity(&game, PLAYER9), 1005);

            ts::return_shared(game);
        };

        // Finalize round 1
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let mut badge_registry = ts::take_shared<BadgeRegistry>(&scenario);
            let mut clock = create_clock(&mut scenario);

            // Fast forward past deadline
            clock::increment_for_testing(&mut clock, 120_001);

            battle_royale::finalize_round(&mut game, &mut badge_registry, &clock, ts::ctx(&mut scenario));

            // Check results: Depends on who the questioner was
            // Case 1: If questioner was PLAYER9 → only PLAYER10 voted C → PLAYER10 eliminated
            // Case 2: If questioner was PLAYER10 → only PLAYER9 voted C → PLAYER9 survived (immunity)
            // Case 3: If questioner was neither → both voted C → only PLAYER10 eliminated (PLAYER9 has immunity)
            let (_, status, round, _, eliminated_count, _, _, _) = battle_royale::get_game_info(&game);
            assert!(status == 1, 1006); // Still active
            assert!(round == 2, 1007); // Moved to round 2

            // Check elimination - depends on voting pattern and who was questioner
            let player9_eliminated = battle_royale::is_player_eliminated(&game, PLAYER9);
            let player10_eliminated = battle_royale::is_player_eliminated(&game, PLAYER10);

            // Debug: Print questioner and elimination state
            std::debug::print(&std::string::utf8(b"=== Round 1 Results ==="));
            std::debug::print(&questioner);
            std::debug::print(&eliminated_count);
            std::debug::print(&player9_eliminated);
            std::debug::print(&player10_eliminated);

            // PLAYER9 has immunity, so should never be eliminated
            assert!(!player9_eliminated, 1009);

            // Voting analysis based on questioner:
            // Case 1: PLAYER9 is questioner
            //   - PLAYER9 votes A (as questioner)
            //   - Only PLAYER10 votes C, others vote A or B
            //   - Result: PLAYER10 eliminated (only C voter)
            //
            // Case 2: PLAYER10 is questioner
            //   - PLAYER10 votes A (as questioner)
            //   - Only PLAYER9 votes C but has immunity
            //   - Result: No eliminations
            //
            // Case 3: Neither PLAYER9 nor PLAYER10 is questioner
            //   - Questioner votes A, 5 others vote A (total 6 for A)
            //   - 2 players vote B (PLAYER7, PLAYER8)
            //   - 2 players vote C (PLAYER9, PLAYER10)
            //   - Result: B and C tied for minority → all B and C voters eliminated
            //   - But PLAYER9 has immunity, so: PLAYER7, PLAYER8, PLAYER10 eliminated (3 total)

            if (questioner == PLAYER9) {
                // Only PLAYER10 voted C
                assert!(eliminated_count == 1, 1010);
                assert!(player10_eliminated, 1011);
            } else if (questioner == PLAYER10) {
                // Only PLAYER9 voted C but has immunity
                assert!(eliminated_count == 0, 1012);
                assert!(!player10_eliminated, 1013);
            } else {
                // B and C voters eliminated (PLAYER7, PLAYER8, PLAYER10)
                // PLAYER9 protected by immunity
                assert!(eliminated_count == 3, 1014);
                assert!(player10_eliminated, 1015);
                assert!(battle_royale::is_player_eliminated(&game, PLAYER7), 1016);
                assert!(battle_royale::is_player_eliminated(&game, PLAYER8), 1017);
            };

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
            ts::return_shared(badge_registry);
        };

        // ===== ROUND 2 =====
        // Get new questioner
        ts::next_tx(&mut scenario, PLAYER1);
        let questioner2 = {
            let game = ts::take_shared<Game>(&scenario);
            let (_, _, _, _, _, _, q, _) = battle_royale::get_game_info(&game);
            ts::return_shared(game);
            q
        };

        // Questioner asks question for round 2
        ts::next_tx(&mut scenario, questioner2);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            let question = std::string::utf8(b"Second round vote");
            let opt_a = std::string::utf8(b"Option X");
            let opt_b = std::string::utf8(b"Option Y");
            let opt_c = std::string::utf8(b"Option Z");

            battle_royale::ask_question(
                &mut game,
                question,
                opt_a,
                opt_b,
                opt_c,
                1,
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // Remaining players vote (create consensus this time - all vote A)
        // Need to check which players were eliminated in Round 1
        let player7_eliminated = {
            ts::next_tx(&mut scenario, PLAYER1);
            let game = ts::take_shared<Game>(&scenario);
            let result = battle_royale::is_player_eliminated(&game, PLAYER7);
            ts::return_shared(game);
            result
        };

        let player8_eliminated = {
            ts::next_tx(&mut scenario, PLAYER1);
            let game = ts::take_shared<Game>(&scenario);
            let result = battle_royale::is_player_eliminated(&game, PLAYER8);
            ts::return_shared(game);
            result
        };

        i = 0;
        while (i < 10) {
            let player = get_player_address(i);

            // Skip eliminated players and questioner
            let is_eliminated = (player == PLAYER10) ||
                               (player == PLAYER7 && player7_eliminated) ||
                               (player == PLAYER8 && player8_eliminated);

            if (!is_eliminated && player != questioner2) {
                ts::next_tx(&mut scenario, player);
                {
                    let mut game = ts::take_shared<Game>(&scenario);
                    let clock = create_clock(&mut scenario);

                    battle_royale::submit_answer(&mut game, 1, &clock, ts::ctx(&mut scenario));

                    clock::destroy_for_testing(clock);
                    ts::return_shared(game);
                };
            };

            i = i + 1;
        };

        // Finalize round 2 (perfect consensus - everyone voted same)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let mut badge_registry = ts::take_shared<BadgeRegistry>(&scenario);
            let mut clock = create_clock(&mut scenario);

            clock::increment_for_testing(&mut clock, 120_001);

            battle_royale::finalize_round(&mut game, &mut badge_registry, &clock, ts::ctx(&mut scenario));

            // Check results: Perfect consensus, no new eliminations in this round
            let (_, status, round, _, eliminated_count, _, _, _) = battle_royale::get_game_info(&game);
            assert!(status == 1, 1018); // Still active
            assert!(round == 3, 1019); // Moved to round 3
            // eliminated_count could be 0, 1, or 3 depending on who was questioner in Round 1
            // No new eliminations in Round 2 (perfect consensus)

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
            ts::return_shared(badge_registry);
        };

        // ===== ROUND 3 (Final Round) =====
        ts::next_tx(&mut scenario, PLAYER1);
        let questioner3 = {
            let game = ts::take_shared<Game>(&scenario);
            let (_, _, _, _, _, _, q, _) = battle_royale::get_game_info(&game);
            ts::return_shared(game);
            q
        };

        ts::next_tx(&mut scenario, questioner3);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let clock = create_clock(&mut scenario);

            let question = std::string::utf8(b"Final round");
            let opt_a = std::string::utf8(b"End A");
            let opt_b = std::string::utf8(b"End B");
            let opt_c = std::string::utf8(b"End C");

            battle_royale::ask_question(&mut game, question, opt_a, opt_b, opt_c, 1, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
        };

        // All surviving players vote
        i = 0;
        while (i < 10) {
            let player = get_player_address(i);

            // Skip eliminated players and questioner
            let is_eliminated = (player == PLAYER10) ||
                               (player == PLAYER7 && player7_eliminated) ||
                               (player == PLAYER8 && player8_eliminated);

            if (!is_eliminated && player != questioner3) {
                ts::next_tx(&mut scenario, player);
                {
                    let mut game = ts::take_shared<Game>(&scenario);
                    let clock = create_clock(&mut scenario);

                    battle_royale::submit_answer(&mut game, 1, &clock, ts::ctx(&mut scenario));

                    clock::destroy_for_testing(clock);
                    ts::return_shared(game);
                };
            };

            i = i + 1;
        };

        // Finalize round 3 (game ends - max rounds reached)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game = ts::take_shared<Game>(&scenario);
            let mut badge_registry = ts::take_shared<BadgeRegistry>(&scenario);
            let mut clock = create_clock(&mut scenario);

            clock::increment_for_testing(&mut clock, 120_001);

            battle_royale::finalize_round(&mut game, &mut badge_registry, &clock, ts::ctx(&mut scenario));

            // Game should be finished now
            let (_, status, _, _, _, prize_pool, _, _) = battle_royale::get_game_info(&game);
            assert!(status == 2, 1020); // Finished
            assert!(prize_pool > 0, 1021); // Prize pool exists

            // Get winning role separately
            let winning_role = battle_royale::get_winning_role(&game);

            // Verify survivors - count depends on Round 1 questioner
            let survivors = battle_royale::get_survivors(&game);
            let survivor_count = std::vector::length(&survivors);
            // Could be 10 (PLAYER10 questioner, 0 elim), 9 (PLAYER9 questioner, 1 elim),
            // or 7 (neither, 3 elim)
            assert!(survivor_count == 10 || survivor_count == 9 || survivor_count == 7, 1022);

            // ===== DETAILED GAME RESULTS =====
            std::debug::print(&std::string::utf8(b"\n========================================"));
            std::debug::print(&std::string::utf8(b"         GAME RESULTS SUMMARY"));
            std::debug::print(&std::string::utf8(b"========================================"));

            // Winner information
            std::debug::print(&std::string::utf8(b"\n--- WINNER ---"));
            if (winning_role == role_machine::role_citizen()) {
                std::debug::print(&std::string::utf8(b"Winner: CITIZENS"));
            } else if (winning_role == role_machine::role_saboteur()) {
                std::debug::print(&std::string::utf8(b"Winner: SABOTEURS"));
            } else {
                std::debug::print(&std::string::utf8(b"Winner: NONE (Max rounds reached)"));
            };

            // Prize pool
            std::debug::print(&std::string::utf8(b"\n--- PRIZE POOL ---"));
            std::debug::print(&prize_pool);

            // Survivors
            std::debug::print(&std::string::utf8(b"\n--- SURVIVORS ---"));
            std::debug::print(&std::string::utf8(b"Total survivors:"));
            std::debug::print(&survivor_count);
            std::debug::print(&std::string::utf8(b"Survivor addresses:"));
            std::debug::print(&survivors);

            clock::destroy_for_testing(clock);
            ts::return_shared(game);
            ts::return_shared(badge_registry);
        };

        // ===== DETAILED PLAYER INFORMATION =====
        std::debug::print(&std::string::utf8(b"\n========================================"));
        std::debug::print(&std::string::utf8(b"      INDIVIDUAL PLAYER DETAILS"));
        std::debug::print(&std::string::utf8(b"========================================"));

        // Check each player's role, status, NFT, and reputation
        let mut player_idx = 0u64;
        while (player_idx < 10) {
            let player_addr = get_player_address(player_idx);

            ts::next_tx(&mut scenario, PLAYER1);
            {
                let game = ts::take_shared<Game>(&scenario);
                let badge_registry = ts::take_shared<BadgeRegistry>(&scenario);

                // Player header
                std::debug::print(&std::string::utf8(b"\n--- PLAYER"));
                std::debug::print(&(player_idx + 1));
                std::debug::print(&std::string::utf8(b"---"));
                std::debug::print(&std::string::utf8(b"Address:"));
                std::debug::print(&player_addr);

                // Role - roles are kept secret in the game design
                // We can only know the overall distribution, not individual roles
                std::debug::print(&std::string::utf8(b"Role: HIDDEN (game design keeps roles secret)"));

                // Elimination status
                let is_eliminated = battle_royale::is_player_eliminated(&game, player_addr);
                std::debug::print(&std::string::utf8(b"Status:"));
                if (is_eliminated) {
                    std::debug::print(&std::string::utf8(b"ELIMINATED"));
                } else {
                    std::debug::print(&std::string::utf8(b"SURVIVED"));
                };

                // Immunity usage
                let used_immunity = battle_royale::has_used_immunity(&game, player_addr);
                if (used_immunity) {
                    std::debug::print(&std::string::utf8(b"Used Immunity: YES"));
                };

                // Reputation badge
                if (reputation::has_badge(&badge_registry, player_addr)) {
                    std::debug::print(&std::string::utf8(b"Has Reputation Badge: YES"));
                } else {
                    std::debug::print(&std::string::utf8(b"Has Reputation Badge: NO"));
                };

                ts::return_shared(game);
                ts::return_shared(badge_registry);
            };

            // Check for PlayerTicket NFT
            ts::next_tx(&mut scenario, player_addr);
            {
                let has_nft = ts::has_most_recent_for_address<PlayerTicket>(player_addr);
                std::debug::print(&std::string::utf8(b"Has PlayerTicket NFT:"));
                if (has_nft) {
                    std::debug::print(&std::string::utf8(b"YES"));
                } else {
                    std::debug::print(&std::string::utf8(b"NO"));
                };
            };

            player_idx = player_idx + 1;
        };

        // ===== REPUTATION DETAILS FOR SURVIVORS =====
        std::debug::print(&std::string::utf8(b"\n========================================"));
        std::debug::print(&std::string::utf8(b"       REPUTATION BADGE DETAILS"));
        std::debug::print(&std::string::utf8(b"========================================"));

        player_idx = 0;
        while (player_idx < 10) {
            let player_addr = get_player_address(player_idx);

            ts::next_tx(&mut scenario, player_addr);
            {
                let badge_registry = ts::take_shared<BadgeRegistry>(&scenario);

                if (reputation::has_badge(&badge_registry, player_addr)) {
                    // Try to get badge details
                    if (ts::has_most_recent_for_address<ReputationBadge>(player_addr)) {
                        let badge = ts::take_from_address<ReputationBadge>(&scenario, player_addr);
                        let (games_played, games_won, points, level) = reputation::get_badge_stats(&badge);

                        std::debug::print(&std::string::utf8(b"\n--- PLAYER"));
                        std::debug::print(&(player_idx + 1));
                        std::debug::print(&std::string::utf8(b"Reputation ---"));
                        std::debug::print(&std::string::utf8(b"Games Played:"));
                        std::debug::print(&games_played);
                        std::debug::print(&std::string::utf8(b"Games Won:"));
                        std::debug::print(&games_won);
                        std::debug::print(&std::string::utf8(b"Points:"));
                        std::debug::print(&points);
                        std::debug::print(&std::string::utf8(b"Level:"));
                        std::debug::print(&level);

                        ts::return_to_address(player_addr, badge);
                    };
                };

                ts::return_shared(badge_registry);
            };

            player_idx = player_idx + 1;
        };

        std::debug::print(&std::string::utf8(b"\n========================================"));
        std::debug::print(&std::string::utf8(b"          TEST COMPLETE"));
        std::debug::print(&std::string::utf8(b"========================================\n"));

        // Verify PlayerTickets were minted for at least one player
        ts::next_tx(&mut scenario, PLAYER1);
        {
            assert!(ts::has_most_recent_for_address<PlayerTicket>(PLAYER1), 1017);
        };

        ts::end(scenario);
    }
}
