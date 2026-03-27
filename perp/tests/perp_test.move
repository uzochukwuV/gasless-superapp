#[test_only]
module perp::perp_tests {
    use one::test_scenario::{Self, Scenario};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::clock::{Self, Clock};
    use std::string;

    use perp::perp_types;
    use perp::perp_config::{Self, ConfigManager};
    use perp::perp_vault::{Self, Vault};
    use perp::perp_oracle::{Self, Oracle};
    use perp::perp_broker::{Self, BrokerManager};
    use perp::perp_trading::{Self, TradingStorage, Position};
    use perp::perp_orderbook::{Self, OrderBookManager};
    use perp::perp_insurance::{Self, InsuranceFund};

    // ============================================
    // TEST CONSTANTS
    // ============================================

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA11CE;
    const BOB: address = @0xB0B;

    // Price precision: 1e10
    const BTC_PRICE: u64 = 500000000000000; // $50,000
    const ETH_PRICE: u64 = 30000000000000;  // $3,000

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    fun setup_test(): Scenario {
        test_scenario::begin(ADMIN)
    }

    fun create_clock(scenario: &mut Scenario): Clock {
        clock::create_for_testing(test_scenario::ctx(scenario))
    }

    fun mint_oct(amount: u64, scenario: &mut Scenario): Coin<OCT> {
        coin::mint_for_testing<OCT>(amount, test_scenario::ctx(scenario))
    }

    // ============================================
    // PERP_TYPES TESTS
    // ============================================

    #[test]
    fun test_signed_value_operations() {
        // Test positive values
        let a = perp_types::new_signed(100, false);
        let b = perp_types::new_signed(50, false);
        let result = perp_types::add_signed(a, b);
        assert!(perp_types::signed_value(&result) == 150, 0);
        assert!(!perp_types::signed_is_negative(&result), 1);

        // Test negative values
        let c = perp_types::new_signed(100, true);
        let d = perp_types::new_signed(50, true);
        let result2 = perp_types::add_signed(c, d);
        assert!(perp_types::signed_value(&result2) == 150, 2);
        assert!(perp_types::signed_is_negative(&result2), 3);

        // Test mixed: positive + negative (positive larger)
        let e = perp_types::new_signed(100, false);
        let f = perp_types::new_signed(30, true);
        let result3 = perp_types::add_signed(e, f);
        assert!(perp_types::signed_value(&result3) == 70, 4);
        assert!(!perp_types::signed_is_negative(&result3), 5);

        // Test mixed: positive + negative (negative larger)
        let g = perp_types::new_signed(30, false);
        let h = perp_types::new_signed(100, true);
        let result4 = perp_types::add_signed(g, h);
        assert!(perp_types::signed_value(&result4) == 70, 6);
        assert!(perp_types::signed_is_negative(&result4), 7);
    }

    #[test]
    fun test_zero_signed() {
        let zero = perp_types::zero_signed();
        assert!(perp_types::signed_value(&zero) == 0, 0);
        assert!(!perp_types::signed_is_negative(&zero), 1);
    }

    #[test]
    fun test_leverage_margin_creation() {
        let lm = perp_types::new_leverage_margin(
            1000000000000, // $1000 notional
            1,             // tier 1
            100,           // 100x max leverage
            500,           // 5% initial margin call
            900            // 9% liquidation
        );

        assert!(perp_types::lm_notional(&lm) == 1000000000000, 0);
        assert!(perp_types::lm_tier(&lm) == 1, 1);
        assert!(perp_types::lm_max_leverage(&lm) == 100, 2);
        assert!(perp_types::lm_initial_lost_p(&lm) == 500, 3);
        assert!(perp_types::lm_liq_lost_p(&lm) == 900, 4);
    }

    #[test]
    fun test_fee_config_creation() {
        let fc = perp_types::new_fee_config(
            string::utf8(b"crypto"),
            0,
            10,     // 0.1% open fee
            10,     // 0.1% close fee
            10000,  // 10% PnL share
            5000    // 5% min close fee
        );

        assert!(perp_types::fc_open_fee_p(&fc) == 10, 0);
        assert!(perp_types::fc_close_fee_p(&fc) == 10, 1);
        assert!(perp_types::fc_share_p(&fc) == 10000, 2);
        assert!(perp_types::fc_min_close_fee_p(&fc) == 5000, 3);
        assert!(perp_types::fc_enabled(&fc), 4);
    }

    #[test]
    fun test_slippage_config_creation() {
        let sc = perp_types::new_slippage_config(
            string::utf8(b"crypto"),
            0,
            1000000000000,  // $1000 1% depth above
            1000000000000,  // $1000 1% depth below
            10,             // 0.1% base long slippage
            10,             // 0.1% base short slippage
            500000000000,   // $500 threshold long
            500000000000    // $500 threshold short
        );

        assert!(perp_types::sc_one_pct_depth_above(&sc) == 1000000000000, 0);
        assert!(perp_types::sc_one_pct_depth_below(&sc) == 1000000000000, 1);
        assert!(perp_types::sc_slippage_long_p(&sc) == 10, 2);
        assert!(perp_types::sc_slippage_short_p(&sc) == 10, 3);
        assert!(perp_types::sc_long_threshold(&sc) == 500000000000, 4);
        assert!(perp_types::sc_short_threshold(&sc) == 500000000000, 5);
        assert!(perp_types::sc_enabled(&sc), 6);
    }

    #[test]
    fun test_constants() {
        // Test precision constants
        assert!(perp_types::bps() == 10000, 0);
        assert!(perp_types::precision_5() == 100000, 1);
        assert!(perp_types::price_precision() == 10000000000, 2);

        // Test pair status constants
        assert!(perp_types::pair_active() == 0, 3);
        assert!(perp_types::pair_close_only() == 1, 4);
        assert!(perp_types::pair_closed() == 2, 5);

        // Test pair type constants
        assert!(perp_types::pair_crypto() == 0, 6);
        assert!(perp_types::pair_forex() == 1, 7);
        assert!(perp_types::pair_commodities() == 2, 8);
        assert!(perp_types::pair_indices() == 3, 9);

        // Test order type constants
        assert!(perp_types::order_market() == 0, 10);
        assert!(perp_types::order_limit() == 1, 11);
        assert!(perp_types::order_stop_market() == 2, 12);
        assert!(perp_types::order_stop_limit() == 3, 13);

        // Test margin mode constants
        assert!(perp_types::margin_isolated() == 0, 14);
        assert!(perp_types::margin_cross() == 1, 15);
    }

    // ============================================
    // PERP_CONFIG TESTS
    // ============================================

    #[test]
    fun test_config_initialization() {
        let mut scenario = setup_test();

        // Initialize config
        {
            perp_config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // Check config was created
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let config = test_scenario::take_shared<ConfigManager>(&scenario);
            assert!(perp_config::is_trading_enabled(&config), 0);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_pair() {
        let mut scenario = setup_test();

        {
            perp_config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<ConfigManager>(&scenario);

            perp_config::add_pair(
                &mut config,
                string::utf8(b"BTC/USD"),  // name
                string::utf8(b"BTC"),      // base
                perp_types::pair_crypto(),
                0,                         // fee_config_index
                0,                         // slippage_config_index
                10000000000000000,         // $10M max long OI
                10000000000000000,         // $10M max short OI
                test_scenario::ctx(&mut scenario)
            );

            assert!(perp_config::pair_exists(&config, string::utf8(b"BTC")), 0);
            assert!(perp_config::is_pair_active(&config, string::utf8(b"BTC")), 1);

            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_set_leverage_margins() {
        let mut scenario = setup_test();

        {
            perp_config::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<ConfigManager>(&scenario);

            // Add pair first
            perp_config::add_pair(
                &mut config,
                string::utf8(b"BTC/USD"),
                string::utf8(b"BTC"),
                perp_types::pair_crypto(),
                0, 0,
                10000000000000000,
                10000000000000000,
                test_scenario::ctx(&mut scenario)
            );

            // Set leverage margins
            perp_config::set_leverage_margins(
                &mut config,
                string::utf8(b"BTC"),
                vector[1u16],                  // tiers
                vector[100000000000000u64],    // notionals ($10k)
                vector[125u16],                // max leverages
                vector[100u16],                // initial lost %
                vector[50u16],                 // liq lost %
                test_scenario::ctx(&scenario)
            );

            let max_lev = perp_config::get_max_leverage(&config, string::utf8(b"BTC"), 50000000000000u64); // $5k
            assert!(max_lev == 125, 0);

            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    // ============================================
    // PERP_VAULT TESTS
    // ============================================

    #[test]
    fun test_vault_initialization() {
        let mut scenario = setup_test();

        {
            perp_vault::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let vault = test_scenario::take_shared<Vault>(&scenario);

            assert!(perp_vault::total_liquidity(&vault) == 0, 0);
            assert!(perp_vault::available_liquidity(&vault) == 0, 1);
            assert!(perp_vault::total_lp_supply(&vault) == 0, 2);
            assert!(!perp_vault::is_paused(&vault), 3);

            test_scenario::return_shared(vault);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_liquidity() {
        let mut scenario = setup_test();

        {
            perp_vault::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut vault = test_scenario::take_shared<Vault>(&scenario);
            let clock = create_clock(&mut scenario);
            let payment = mint_oct(1000000, &mut scenario); // 1M OCT

            perp_vault::add_liquidity(
                &mut vault,
                payment,
                1000000,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            assert!(perp_vault::total_liquidity(&vault) == 1000000, 0);
            assert!(perp_vault::total_lp_supply(&vault) == 1000000, 1); // 1:1 for first deposit
            assert!(perp_vault::get_lp_balance(&vault, ALICE) == 1000000, 2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(vault);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_reserve_and_release() {
        let mut scenario = setup_test();

        {
            perp_vault::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // Add liquidity first
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut vault = test_scenario::take_shared<Vault>(&scenario);
            let clock = create_clock(&mut scenario);
            let payment = mint_oct(1000000, &mut scenario);

            perp_vault::add_liquidity(&mut vault, payment, 1000000, &clock, test_scenario::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(vault);
        };

        // Test reserve
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut vault = test_scenario::take_shared<Vault>(&scenario);

            perp_vault::reserve(&mut vault, 500000);

            assert!(perp_vault::total_liquidity(&vault) == 1000000, 0);
            assert!(perp_vault::available_liquidity(&vault) == 500000, 1);
            assert!(perp_vault::reserved_liquidity(&vault) == 500000, 2);

            // Test release
            perp_vault::release(&mut vault, 200000);

            assert!(perp_vault::available_liquidity(&vault) == 700000, 3);
            assert!(perp_vault::reserved_liquidity(&vault) == 300000, 4);

            test_scenario::return_shared(vault);
        };

        test_scenario::end(scenario);
    }

    // ============================================
    // PERP_ORACLE TESTS
    // ============================================

    #[test]
    fun test_oracle_initialization() {
        let mut scenario = setup_test();

        {
            perp_oracle::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let oracle = test_scenario::take_shared<Oracle>(&scenario);
            // Oracle created successfully
            test_scenario::return_shared(oracle);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_update_price() {
        let mut scenario = setup_test();

        {
            perp_oracle::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut oracle = test_scenario::take_shared<Oracle>(&scenario);
            let clock = create_clock(&mut scenario);

            perp_oracle::update_price(
                &mut oracle,
                string::utf8(b"BTC"),
                BTC_PRICE,
                1000, // confidence
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            let price = perp_oracle::get_price(&oracle, string::utf8(b"BTC"), &clock);
            assert!(price == BTC_PRICE, 0);

            assert!(perp_oracle::is_price_fresh(&oracle, string::utf8(b"BTC"), &clock), 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(oracle);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_batch_update_prices() {
        let mut scenario = setup_test();

        {
            perp_oracle::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut oracle = test_scenario::take_shared<Oracle>(&scenario);
            let clock = create_clock(&mut scenario);

            let tokens = vector[
                string::utf8(b"BTC"),
                string::utf8(b"ETH")
            ];
            let prices = vector[BTC_PRICE, ETH_PRICE];
            let confidences = vector[1000u64, 1000u64];

            perp_oracle::update_prices_batch(
                &mut oracle,
                tokens,
                prices,
                confidences,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            let btc_price = perp_oracle::get_price(&oracle, string::utf8(b"BTC"), &clock);
            let eth_price = perp_oracle::get_price(&oracle, string::utf8(b"ETH"), &clock);

            assert!(btc_price == BTC_PRICE, 0);
            assert!(eth_price == ETH_PRICE, 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(oracle);
        };

        test_scenario::end(scenario);
    }

    // ============================================
    // PERP_BROKER TESTS
    // ============================================

    #[test]
    fun test_broker_initialization() {
        let mut scenario = setup_test();

        {
            perp_broker::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let manager = test_scenario::take_shared<BrokerManager>(&scenario);

            assert!(perp_broker::broker_count(&manager) == 1, 0); // Default broker
            assert!(perp_broker::default_broker_id(&manager) == 1, 1);

            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_add_broker() {
        let mut scenario = setup_test();

        {
            perp_broker::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut manager = test_scenario::take_shared<BrokerManager>(&scenario);

            perp_broker::add_broker(
                &mut manager,
                string::utf8(b"TestBroker"),
                string::utf8(b"https://test.broker"),
                ALICE,
                5000,  // 50% commission
                2000,  // 20% DAO share
                3000,  // 30% LP pool
                test_scenario::ctx(&mut scenario)
            );

            assert!(perp_broker::broker_count(&manager) == 2, 0);

            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    // ============================================
    // PERP_TRADING TESTS
    // ============================================

    #[test]
    fun test_trading_initialization() {
        let mut scenario = setup_test();

        {
            perp_trading::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let storage = test_scenario::take_shared<TradingStorage>(&scenario);
            // Storage created successfully
            test_scenario::return_shared(storage);
        };

        test_scenario::end(scenario);
    }

    // Integration test: Full trading flow
    #[test]
    fun test_open_position_direct() {
        let mut scenario = setup_test();

        // Initialize all modules
        {
            perp_config::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_vault::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_oracle::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_broker::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_trading::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // Setup: Add pair and liquidity
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<ConfigManager>(&scenario);
            let mut vault = test_scenario::take_shared<Vault>(&scenario);
            let mut oracle = test_scenario::take_shared<Oracle>(&scenario);
            let clock = create_clock(&mut scenario);

            // Add BTC pair
            perp_config::add_pair(
                &mut config,
                string::utf8(b"BTC/USD"),
                string::utf8(b"BTC"),
                perp_types::pair_crypto(),
                0, 0,
                100000000000000000u64, // $100M max OI
                100000000000000000u64,
                test_scenario::ctx(&mut scenario)
            );

            // Set leverage margins
            perp_config::set_leverage_margins(
                &mut config,
                string::utf8(b"BTC"),
                vector[1u16],
                vector[1000000000000000u64], // $100k
                vector[100u16], // 100x
                vector[100u16],
                vector[50u16],
                test_scenario::ctx(&scenario)
            );

            // Add liquidity
            let liquidity = mint_oct(100000000000, &mut scenario); // 100B OCT
            perp_vault::add_liquidity(&mut vault, liquidity, 100000000000, &clock, test_scenario::ctx(&mut scenario));

            // Set BTC price
            perp_oracle::update_price(
                &mut oracle,
                string::utf8(b"BTC"),
                BTC_PRICE,
                1000,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(oracle);
        };

        // Open a position
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut storage = test_scenario::take_shared<TradingStorage>(&scenario);
            let mut config = test_scenario::take_shared<ConfigManager>(&scenario);
            let mut vault = test_scenario::take_shared<Vault>(&scenario);
            let oracle = test_scenario::take_shared<Oracle>(&scenario);
            let mut broker_manager = test_scenario::take_shared<BrokerManager>(&scenario);
            let clock = create_clock(&mut scenario);

            let margin = mint_oct(1000000000, &mut scenario); // 1B OCT margin

            perp_trading::open_position_direct(
                &mut storage,
                &mut config,
                &mut vault,
                &mut broker_manager,
                &oracle,
                margin,
                string::utf8(b"BTC"),
                10, // 10x leverage
                true, // long
                0, // no stop loss
                0, // no take profit
                1, // default broker
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(broker_manager);
        };

        // Verify position was created
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            // Position should be transferred to Alice
            let position = test_scenario::take_from_sender<Position>(&scenario);

            assert!(perp_trading::position_trader(&position) == ALICE, 0);
            assert!(perp_trading::position_is_long(&position), 1);
            assert!(perp_trading::position_leverage(&position) == 10, 2);

            test_scenario::return_to_sender(&scenario, position);
        };

        test_scenario::end(scenario);
    }

    // ============================================
    // PERP_ORDERBOOK TESTS
    // ============================================

    #[test]
    fun test_orderbook_initialization() {
        let mut scenario = setup_test();

        {
            perp_orderbook::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let manager = test_scenario::take_shared<OrderBookManager>(&scenario);

            assert!(perp_orderbook::is_enabled(&manager), 0);
            assert!(perp_orderbook::total_locked_margin(&manager) == 0, 1);

            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_place_limit_order() {
        let mut scenario = setup_test();

        {
            perp_orderbook::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut manager = test_scenario::take_shared<OrderBookManager>(&scenario);
            let clock = create_clock(&mut scenario);
            let margin = mint_oct(1000000, &mut scenario);

            perp_orderbook::place_limit_order(
                &mut manager,
                string::utf8(b"BTC"),
                true,  // long
                BTC_PRICE - 1000000000000, // limit price below current
                margin,
                10,    // leverage
                perp_types::margin_isolated(),
                0,     // no stop loss
                0,     // no take profit
                1,     // broker id
                false, // not reduce only
                false, // not post only
                0,     // default expiry
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            assert!(perp_orderbook::get_user_order_count(&manager, ALICE) == 1, 0);
            assert!(perp_orderbook::total_locked_margin(&manager) == 1000000, 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(manager);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_order() {
        let mut scenario = setup_test();

        {
            perp_orderbook::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // Place order
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut manager = test_scenario::take_shared<OrderBookManager>(&scenario);
            let clock = create_clock(&mut scenario);
            let margin = mint_oct(1000000, &mut scenario);

            perp_orderbook::place_limit_order(
                &mut manager,
                string::utf8(b"BTC"),
                true,
                BTC_PRICE,
                margin,
                10,
                perp_types::margin_isolated(),
                0, 0, 1,
                false, false, 0,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(manager);
        };

        // Cancel order
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut manager = test_scenario::take_shared<OrderBookManager>(&scenario);

            perp_orderbook::cancel_order(&mut manager, 1, test_scenario::ctx(&mut scenario));

            assert!(perp_orderbook::get_user_order_count(&manager, ALICE) == 0, 0);

            test_scenario::return_shared(manager);
        };

        // Check refund received
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let refund = test_scenario::take_from_sender<Coin<OCT>>(&scenario);
            assert!(coin::value(&refund) == 1000000, 0);
            test_scenario::return_to_sender(&scenario, refund);
        };

        test_scenario::end(scenario);
    }

    // ============================================
    // PERP_INSURANCE TESTS
    // ============================================

    #[test]
    fun test_insurance_initialization() {
        let mut scenario = setup_test();

        {
            perp_insurance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let fund = test_scenario::take_shared<InsuranceFund>(&scenario);

            assert!(perp_insurance::balance(&fund) == 0, 0);
            assert!(perp_insurance::total_deposits(&fund) == 0, 1);
            assert!(perp_insurance::total_payouts(&fund) == 0, 2);
            assert!(perp_insurance::is_healthy(&fund), 3);

            test_scenario::return_shared(fund);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_insurance_deposit() {
        let mut scenario = setup_test();

        {
            perp_insurance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut fund = test_scenario::take_shared<InsuranceFund>(&scenario);
            let deposit = mint_oct(1000000, &mut scenario);

            perp_insurance::deposit(&mut fund, deposit, test_scenario::ctx(&mut scenario));

            assert!(perp_insurance::balance(&fund) == 1000000, 0);
            assert!(perp_insurance::total_deposits(&fund) == 1000000, 1);

            test_scenario::return_shared(fund);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_insurance_cover_bad_debt() {
        let mut scenario = setup_test();

        {
            perp_insurance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // Deposit to insurance
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut fund = test_scenario::take_shared<InsuranceFund>(&scenario);
            let deposit = mint_oct(10000000, &mut scenario); // 10M

            perp_insurance::deposit(&mut fund, deposit, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(fund);
        };

        // Cover bad debt
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fund = test_scenario::take_shared<InsuranceFund>(&scenario);

            let payout = perp_insurance::cover_bad_debt(
                &mut fund,
                string::utf8(b"BTC"),
                500000, // 500k bad debt
                test_scenario::ctx(&mut scenario)
            );

            // Check payout (limited by max utilization)
            let payout_value = coin::value(&payout);
            assert!(payout_value > 0, 0);
            assert!(perp_insurance::total_payouts(&fund) == payout_value, 1);

            // Burn payout for test
            coin::burn_for_testing(payout);

            test_scenario::return_shared(fund);
        };

        test_scenario::end(scenario);
    }

    #[test]
    fun test_should_trigger_adl() {
        let mut scenario = setup_test();

        {
            perp_insurance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut fund = test_scenario::take_shared<InsuranceFund>(&scenario);

            // Set ADL threshold
            perp_insurance::set_adl_threshold(&mut fund, 1000000, test_scenario::ctx(&scenario));

            // With 0 balance and threshold of 1M, ADL should trigger
            assert!(perp_insurance::should_trigger_adl(&fund, 100), 0);

            test_scenario::return_shared(fund);
        };

        test_scenario::end(scenario);
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    #[test]
    fun test_full_trading_cycle() {
        let mut scenario = setup_test();

        // Initialize all modules
        {
            perp_config::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_vault::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_oracle::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_broker::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_trading::init_for_testing(test_scenario::ctx(&mut scenario));
            perp_insurance::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        // Setup
        test_scenario::next_tx(&mut scenario, ADMIN);
        {
            let mut config = test_scenario::take_shared<ConfigManager>(&scenario);
            let mut vault = test_scenario::take_shared<Vault>(&scenario);
            let mut oracle = test_scenario::take_shared<Oracle>(&scenario);
            let mut insurance = test_scenario::take_shared<InsuranceFund>(&scenario);
            let clock = create_clock(&mut scenario);

            // Add pair
            perp_config::add_pair(
                &mut config,
                string::utf8(b"ETH/USD"),
                string::utf8(b"ETH"),
                perp_types::pair_crypto(),
                0, 0,
                100000000000000000u64,
                100000000000000000u64,
                test_scenario::ctx(&mut scenario)
            );

            // Set leverage margins
            perp_config::set_leverage_margins(
                &mut config,
                string::utf8(b"ETH"),
                vector[1u16],
                vector[1000000000000000u64],
                vector[50u16],
                vector[100u16],
                vector[50u16],
                test_scenario::ctx(&scenario)
            );

            // Add liquidity
            let liquidity = mint_oct(1000000000000, &mut scenario);
            perp_vault::add_liquidity(&mut vault, liquidity, 1000000000000, &clock, test_scenario::ctx(&mut scenario));

            // Set price
            perp_oracle::update_price(
                &mut oracle,
                string::utf8(b"ETH"),
                ETH_PRICE,
                1000,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            // Fund insurance
            let insurance_deposit = mint_oct(100000000, &mut scenario);
            perp_insurance::deposit(&mut insurance, insurance_deposit, test_scenario::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(insurance);
        };

        // Open long position
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut storage = test_scenario::take_shared<TradingStorage>(&scenario);
            let mut config = test_scenario::take_shared<ConfigManager>(&scenario);
            let mut vault = test_scenario::take_shared<Vault>(&scenario);
            let oracle = test_scenario::take_shared<Oracle>(&scenario);
            let mut broker_manager = test_scenario::take_shared<BrokerManager>(&scenario);
            let clock = create_clock(&mut scenario);

            let margin = mint_oct(10000000000, &mut scenario); // 10B margin

            perp_trading::open_position_direct(
                &mut storage,
                &mut config,
                &mut vault,
                &mut broker_manager,
                &oracle,
                margin,
                string::utf8(b"ETH"),
                20, // 20x leverage
                true, // long
                0, 0, 1,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(broker_manager);
        };

        // Verify position and close it
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            let mut storage = test_scenario::take_shared<TradingStorage>(&scenario);
            let mut config = test_scenario::take_shared<ConfigManager>(&scenario);
            let mut vault = test_scenario::take_shared<Vault>(&scenario);
            let oracle = test_scenario::take_shared<Oracle>(&scenario);
            let mut broker_manager = test_scenario::take_shared<BrokerManager>(&scenario);
            let clock = create_clock(&mut scenario);

            let position = test_scenario::take_from_sender<Position>(&scenario);

            // Close position
            perp_trading::close_position(
                &mut storage,
                &mut config,
                &mut vault,
                &mut broker_manager,
                &oracle,
                position,
                &clock,
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(config);
            test_scenario::return_shared(vault);
            test_scenario::return_shared(oracle);
            test_scenario::return_shared(broker_manager);
        };

        // Check Alice received payout
        test_scenario::next_tx(&mut scenario, ALICE);
        {
            // Alice should have received her margin back (minus fees)
            // The exact amount depends on PnL calculation
            let has_payout = test_scenario::has_most_recent_for_sender<Coin<OCT>>(&scenario);
            assert!(has_payout, 0);
        };

        test_scenario::end(scenario);
    }
}
