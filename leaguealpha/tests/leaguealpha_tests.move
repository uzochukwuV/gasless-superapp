#[test_only]
module leaguealpha::leaguealpha_tests {
    use one::test_scenario::{Self as ts, Scenario};
    use one::clock::{Self, Clock};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use leaguealpha::game_engine::{Self, GameState, MatchData};
    use leaguealpha::betting_pool::{Self, LiquidityVault, MatchAccounting, Bet, LPToken};

    const ADMIN: address = @0xAD;
    const PLAYER1: address = @0x1;
    const PLAYER2: address = @0x2;

    const LP_DEPOSIT: u64 = 100_000_000_000_000; // 100,000 OCT
    const BET_AMOUNT: u64 = 1_000_000_000_000; // 1,000 OCT

    fun create_clock(scenario: &mut Scenario): Clock {
        let mut clock = clock::create_for_testing(ts::ctx(scenario));
        clock::set_for_testing(&mut clock, 1000000);
        clock
    }

    fun mint_oct(scenario: &mut Scenario, amount: u64): Coin<OCT> {
        coin::mint_for_testing<OCT>(amount, ts::ctx(scenario))
    }

    #[test]
    fun test_init_both_modules() {
        let mut scenario = ts::begin(ADMIN);

        {
            game_engine::init_for_testing(ts::ctx(&mut scenario));
            betting_pool::init_for_testing(ts::ctx(&mut scenario));
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_shared<GameState>(), 0);
            assert!(ts::has_most_recent_shared<LiquidityVault>(), 1);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_lp_deposit_withdraw() {
        let mut scenario = ts::begin(ADMIN);
        betting_pool::init_for_testing(ts::ctx(&mut scenario));

        // LP deposits
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut vault = ts::take_shared<LiquidityVault>(&scenario);
            let payment = mint_oct(&mut scenario, LP_DEPOSIT);

            betting_pool::add_liquidity(&mut vault, payment, ts::ctx(&mut scenario));

            ts::return_shared(vault);
        };

        // Check LP token received
        ts::next_tx(&mut scenario, PLAYER1);
        {
            assert!(ts::has_most_recent_for_address<LPToken>(PLAYER1), 100);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_create_match() {
        let mut scenario = ts::begin(ADMIN);
        game_engine::init_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game_state = ts::take_shared<GameState>(&scenario);
            let clock = create_clock(&mut scenario);

            game_engine::create_match(
                &mut game_state,
                0, // home
                1, // away
                10_800_000, // 3 hours
                &clock,
                ts::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            ts::return_shared(game_state);
        };

        // Admin should own the MatchData
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_for_address<MatchData>(ADMIN), 200);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_seed_match() {
        let mut scenario = ts::begin(ADMIN);
        game_engine::init_for_testing(ts::ctx(&mut scenario));
        betting_pool::init_for_testing(ts::ctx(&mut scenario));

        // LP deposits liquidity
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut vault = ts::take_shared<LiquidityVault>(&scenario);
            let payment = mint_oct(&mut scenario, LP_DEPOSIT);
            betting_pool::add_liquidity(&mut vault, payment, ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };

        // Create match
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game_state = ts::take_shared<GameState>(&scenario);
            let clock = create_clock(&mut scenario);
            game_engine::create_match(&mut game_state, 0, 1, 10_800_000, &clock, ts::ctx(&mut scenario));
            clock::destroy_for_testing(clock);
            ts::return_shared(game_state);
        };

        // Seed match pool
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut vault = ts::take_shared<LiquidityVault>(&scenario);
            let match_data = ts::take_from_address<MatchData>(&scenario, ADMIN);

            betting_pool::seed_match(&mut vault, &match_data, ts::ctx(&mut scenario));

            ts::return_shared(vault);
            ts::return_to_address(ADMIN, match_data);
        };

        // Check MatchAccounting was created as shared object
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_shared<MatchAccounting>(), 300);
            let accounting = ts::take_shared<MatchAccounting>(&scenario);
            assert!(betting_pool::is_match_seeded(&accounting), 301);
            ts::return_shared(accounting);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_create_match_same_team_fails() {
        let mut scenario = ts::begin(ADMIN);
        game_engine::init_for_testing(ts::ctx(&mut scenario));

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game_state = ts::take_shared<GameState>(&scenario);
            let clock = create_clock(&mut scenario);

            game_engine::create_match(&mut game_state, 0, 0, 10_800_000, &clock, ts::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            ts::return_shared(game_state);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure]
    fun test_seed_match_twice_fails() {
        let mut scenario = ts::begin(ADMIN);
        game_engine::init_for_testing(ts::ctx(&mut scenario));
        betting_pool::init_for_testing(ts::ctx(&mut scenario));

        // LP deposits
        ts::next_tx(&mut scenario, PLAYER1);
        {
            let mut vault = ts::take_shared<LiquidityVault>(&scenario);
            let payment = mint_oct(&mut scenario, LP_DEPOSIT);
            betting_pool::add_liquidity(&mut vault, payment, ts::ctx(&mut scenario));
            ts::return_shared(vault);
        };

        // Create match
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut game_state = ts::take_shared<GameState>(&scenario);
            let clock = create_clock(&mut scenario);
            game_engine::create_match(&mut game_state, 0, 1, 10_800_000, &clock, ts::ctx(&mut scenario));
            clock::destroy_for_testing(clock);
            ts::return_shared(game_state);
        };

        // Seed once
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut vault = ts::take_shared<LiquidityVault>(&scenario);
            let match_data = ts::take_from_address<MatchData>(&scenario, ADMIN);
            betting_pool::seed_match(&mut vault, &match_data, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(ADMIN, match_data);
        };

        // Try to seed again — should fail
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut vault = ts::take_shared<LiquidityVault>(&scenario);
            let match_data = ts::take_from_address<MatchData>(&scenario, ADMIN);
            betting_pool::seed_match(&mut vault, &match_data, ts::ctx(&mut scenario));
            ts::return_shared(vault);
            ts::return_to_address(ADMIN, match_data);
        };

        ts::end(scenario);
    }
}
