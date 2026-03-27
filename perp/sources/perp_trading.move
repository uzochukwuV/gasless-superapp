/// Main trading module with positions, pending trades, and execution (based on Astex TradingPortalFacet + LibTrading)
module perp::perp_trading {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::table::{Self, Table};
    use one::balance::{Self, Balance};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::clock::{Self, Clock};
    use one::event;
    use std::string::String;
    use perp::perp_types::{Self, FeeConfig};
    use perp::perp_config::{Self, ConfigManager};
    use perp::perp_vault::{Self, Vault};
    use perp::perp_oracle::{Self, Oracle};
    use perp::perp_broker::{Self, BrokerManager};

    // ============================================
    // CONSTANTS
    // ============================================

    const PENDING_TRADE_EXPIRY_MS: u64 = 300000; // 5 minutes
    const MIN_LEVERAGE: u64 = 1;

    // ============================================
    // STRUCTS - POSITION
    // ============================================

    /// Open position
    public struct Position has key, store {
        id: UID,
        trader: address,
        pair_base: String,
        margin: u64,                    // Collateral amount
        qty: u64,                       // Position size in base units
        leverage: u64,
        is_long: bool,
        entry_price: u64,               // Entry price (1e10)
        liquidation_price: u64,
        opened_at: u64,                 // Block number
        last_funding_update: u64,
        stop_loss: u64,                 // 0 = not set
        take_profit: u64,               // 0 = not set
        holding_fee_rate: u64,          // Holding fee rate at open
        broker_id: u32,
        long_acc_funding_fee_per_share: u128, // Snapshot at open
        margin_mode: u8,                // 0 = Isolated, 1 = Cross
    }

    // ============================================
    // STRUCTS - PENDING TRADE (MEV Protection)
    // ============================================

    /// Pending trade request (2-step execution)
    public struct PendingTrade has store, drop {
        user: address,
        broker_id: u32,
        is_long: bool,
        price: u64,                     // Requested price
        pair_base: String,
        amount_in: u64,                 // Margin amount
        qty: u64,                       // Requested position size
        leverage: u64,
        stop_loss: u64,
        take_profit: u64,
        block_number: u64,
        created_at: u64,
        margin_mode: u8,                // 0 = Isolated, 1 = Cross
    }

    // ============================================
    // STRUCTS - TRADING STORAGE
    // ============================================

    /// Main trading storage
    public struct TradingStorage has key {
        id: UID,
        /// Salt for unique trade hashes
        salt: u64,
        /// Pending trades
        pending_trades: Table<ID, PendingTrade>,
        /// User's open position IDs
        user_positions: Table<address, vector<ID>>,
        /// Accumulated funding fee per share (long side)
        long_acc_funding_fee: Table<String, u128>,
        /// Position info for tracking
        position_info: Table<String, PositionInfo>,
        /// Keeper address for automated execution
        keeper: address,
    }

    /// Aggregated position info per pair
    public struct PositionInfo has store {
        long_qty: u64,
        short_qty: u64,
        last_funding_block: u64,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct TradingStorageCreated has copy, drop {
        storage_id: ID,
    }

    public struct PendingTradeCreated has copy, drop {
        trade_id: ID,
        user: address,
        pair_base: String,
        is_long: bool,
        amount_in: u64,
        leverage: u64,
    }

    public struct PositionOpened has copy, drop {
        position_id: ID,
        trader: address,
        pair_base: String,
        margin: u64,
        qty: u64,
        leverage: u64,
        is_long: bool,
        entry_price: u64,
        liquidation_price: u64,
    }

    public struct PositionClosed has copy, drop {
        position_id: ID,
        trader: address,
        pair_base: String,
        pnl: u64,
        is_profit: bool,
        close_fee: u64,
        funding_fee: u64,
    }

    public struct PositionLiquidated has copy, drop {
        position_id: ID,
        trader: address,
        liquidator: address,
        pair_base: String,
        collateral_seized: u64,
        liquidator_reward: u64,
    }

    public struct TpSlUpdated has copy, drop {
        position_id: ID,
        stop_loss: u64,
        take_profit: u64,
    }

    public struct MarginAdded has copy, drop {
        position_id: ID,
        amount: u64,
        new_margin: u64,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let keeper = tx_context::sender(ctx);

        let storage = TradingStorage {
            id: object::new(ctx),
            salt: 0,
            pending_trades: table::new(ctx),
            user_positions: table::new(ctx),
            long_acc_funding_fee: table::new(ctx),
            position_info: table::new(ctx),
            keeper,
        };

        event::emit(TradingStorageCreated {
            storage_id: object::id(&storage),
        });

        transfer::share_object(storage);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ============================================
    // OPEN POSITION (2-STEP: REQUEST + EXECUTE)
    // ============================================

    /// Step 1: Request to open a position (creates pending trade)
    public entry fun request_open_position(
        storage: &mut TradingStorage,
        config: &ConfigManager,
        vault: &mut Vault,
        oracle: &Oracle,
        mut payment: Coin<OCT>,
        pair_base: String,
        leverage: u64,
        is_long: bool,
        stop_loss: u64,
        take_profit: u64,
        broker_id: u32,
        margin_mode: u8,  // 0 = Isolated, 1 = Cross
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate margin mode
        assert!(margin_mode == perp_types::margin_isolated() || margin_mode == perp_types::margin_cross(),
            perp_types::e_invalid_margin_mode());
        // Validations
        assert!(perp_config::is_trading_enabled(config), perp_types::e_trading_disabled());
        assert!(perp_config::pair_exists(config, pair_base), perp_types::e_pair_not_found());
        assert!(perp_config::is_pair_active(config, pair_base), perp_types::e_pair_closed());
        assert!(!perp_vault::is_paused(vault), perp_types::e_trading_disabled());

        let user = tx_context::sender(ctx);
        let amount_in = coin::value(&payment);
        assert!(amount_in > 0, perp_types::e_insufficient_margin());

        // Validate leverage
        let current_price = perp_oracle::get_price(oracle, pair_base, clock);
        let notional_usd = (amount_in as u128) * (leverage as u128) * (current_price as u128)
            / (perp_types::price_precision() as u128);
        let max_lev = perp_config::get_max_leverage(config, pair_base, (notional_usd as u64));
        assert!(leverage >= MIN_LEVERAGE && leverage <= (max_lev as u64), perp_types::e_leverage_too_high());

        // Calculate qty
        let qty = amount_in * leverage;

        // Check OI limit
        assert!(
            perp_config::can_increase_oi(config, pair_base, is_long, (notional_usd as u64)),
            perp_types::e_oi_limit_exceeded()
        );

        // Check pool has enough liquidity
        assert!(
            perp_vault::available_liquidity(vault) >= qty,
            perp_types::e_insufficient_liquidity()
        );

        // Create pending trade
        let current_time = clock::timestamp_ms(clock);
        let trade_id = object::new(ctx);
        let pending = PendingTrade {
            user,
            broker_id,
            is_long,
            price: current_price,
            pair_base,
            amount_in,
            qty,
            leverage,
            stop_loss,
            take_profit,
            block_number: tx_context::epoch(ctx),
            created_at: current_time,
            margin_mode,
        };

        let id = object::uid_to_inner(&trade_id);
        object::delete(trade_id);

        storage.salt = storage.salt + 1;
        table::add(&mut storage.pending_trades, id, pending);

        // Hold payment in vault
        perp_vault::deposit_margin(vault, payment);

        event::emit(PendingTradeCreated {
            trade_id: id,
            user,
            pair_base,
            is_long,
            amount_in,
            leverage,
        });
    }

    /// Step 2: Execute pending trade (called by keeper after price confirmation)
    public entry fun execute_pending_trade(
        storage: &mut TradingStorage,
        config: &mut ConfigManager,
        vault: &mut Vault,
        broker_manager: &mut BrokerManager,
        oracle: &Oracle,
        trade_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(table::contains(&storage.pending_trades, trade_id), perp_types::e_pending_trade_not_found());

        let pending = table::remove(&mut storage.pending_trades, trade_id);
        let current_time = clock::timestamp_ms(clock);

        // Check expiry
        assert!(
            current_time - pending.created_at <= PENDING_TRADE_EXPIRY_MS,
            perp_types::e_trade_expired()
        );

        // Get current price
        let current_price = perp_oracle::get_price(oracle, pending.pair_base, clock);

        // Calculate slippage-adjusted price
        let slippage_bps = perp_config::calculate_slippage(config, pending.pair_base, pending.is_long, pending.qty);
        let entry_price = if (pending.is_long) {
            current_price + (current_price * slippage_bps) / 10000
        } else {
            current_price - (current_price * slippage_bps) / 10000
        };

        // Calculate fees
        let fee_config = perp_config::get_fee_config(config, pending.pair_base);
        let open_fee = (pending.qty * (perp_types::fc_open_fee_p(&fee_config) as u64)) / 10000;

        assert!(pending.amount_in > open_fee, perp_types::e_insufficient_margin());
        let net_margin = pending.amount_in - open_fee;

        // Record broker commission
        let oct_symbol = std::string::utf8(b"OCT");
        let (_commission, actual_broker_id, dao_amount, lp_amount) = perp_broker::record_commission(
            broker_manager,
            oct_symbol,
            open_fee,
            pending.broker_id,
            ctx
        );

        // Collect fees
        perp_vault::collect_fees(vault, open_fee);

        // Calculate liquidation price
        let liq_threshold = perp_config::get_liquidation_threshold(config, pending.pair_base, pending.qty);
        let liquidation_price = calculate_liquidation_price(
            pending.is_long,
            entry_price,
            net_margin,
            pending.qty,
            liq_threshold
        );

        // Get holding fee rate
        let holding_fee_rate = perp_config::get_holding_fee_rate(config, pending.pair_base, pending.is_long);

        // Get accumulated funding fee
        let long_acc_funding = if (table::contains(&storage.long_acc_funding_fee, pending.pair_base)) {
            *table::borrow(&storage.long_acc_funding_fee, pending.pair_base)
        } else {
            table::add(&mut storage.long_acc_funding_fee, pending.pair_base, 0);
            0
        };

        // Create position
        let position = Position {
            id: object::new(ctx),
            trader: pending.user,
            pair_base: pending.pair_base,
            margin: net_margin,
            qty: pending.qty,
            leverage: pending.leverage,
            is_long: pending.is_long,
            entry_price,
            liquidation_price,
            opened_at: tx_context::epoch(ctx),
            last_funding_update: tx_context::epoch(ctx),
            stop_loss: pending.stop_loss,
            take_profit: pending.take_profit,
            holding_fee_rate,
            broker_id: actual_broker_id,
            long_acc_funding_fee_per_share: long_acc_funding,
            margin_mode: pending.margin_mode,
        };

        let position_id = object::id(&position);

        // Update OI
        let notional_usd = (pending.qty as u128) * (entry_price as u128) / (perp_types::price_precision() as u128);
        perp_config::increase_oi(config, pending.pair_base, pending.is_long, (notional_usd as u64));

        // Reserve liquidity
        perp_vault::reserve(vault, pending.qty);

        // Update position info
        update_position_info(storage, pending.pair_base, pending.is_long, pending.qty, true);

        // Track user positions
        if (!table::contains(&storage.user_positions, pending.user)) {
            table::add(&mut storage.user_positions, pending.user, vector::empty());
        };
        let user_pos = table::borrow_mut(&mut storage.user_positions, pending.user);
        vector::push_back(user_pos, position_id);

        event::emit(PositionOpened {
            position_id,
            trader: pending.user,
            pair_base: pending.pair_base,
            margin: net_margin,
            qty: pending.qty,
            leverage: pending.leverage,
            is_long: pending.is_long,
            entry_price,
            liquidation_price,
        });

        // Transfer position to trader
        transfer::public_transfer(position, pending.user);
    }

    /// Direct open position (single step - for simpler UX, less MEV protection)
    public entry fun open_position_direct(
        storage: &mut TradingStorage,
        config: &mut ConfigManager,
        vault: &mut Vault,
        broker_manager: &mut BrokerManager,
        oracle: &Oracle,
        mut payment: Coin<OCT>,
        pair_base: String,
        leverage: u64,
        is_long: bool,
        stop_loss: u64,
        take_profit: u64,
        broker_id: u32,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validations
        assert!(perp_config::is_trading_enabled(config), perp_types::e_trading_disabled());
        assert!(perp_config::pair_exists(config, pair_base), perp_types::e_pair_not_found());
        assert!(perp_config::is_pair_active(config, pair_base), perp_types::e_pair_closed());
        assert!(!perp_vault::is_paused(vault), perp_types::e_trading_disabled());

        let user = tx_context::sender(ctx);
        let amount_in = coin::value(&payment);
        assert!(amount_in > 0, perp_types::e_insufficient_margin());

        // Get price
        let current_price = perp_oracle::get_price(oracle, pair_base, clock);

        // Calculate qty and notional
        let qty = amount_in * leverage;
        let notional_usd = (qty as u128) * (current_price as u128) / (perp_types::price_precision() as u128);

        // Validate leverage
        let max_lev = perp_config::get_max_leverage(config, pair_base, (notional_usd as u64));
        assert!(leverage >= MIN_LEVERAGE && leverage <= (max_lev as u64), perp_types::e_leverage_too_high());

        // Check OI limit
        assert!(
            perp_config::can_increase_oi(config, pair_base, is_long, (notional_usd as u64)),
            perp_types::e_oi_limit_exceeded()
        );

        // Calculate slippage
        let slippage_bps = perp_config::calculate_slippage(config, pair_base, is_long, qty);
        let entry_price = if (is_long) {
            current_price + (current_price * slippage_bps) / 10000
        } else {
            if (current_price > (current_price * slippage_bps) / 10000) {
                current_price - (current_price * slippage_bps) / 10000
            } else {
                current_price
            }
        };

        // Calculate fees
        let fee_config = perp_config::get_fee_config(config, pair_base);
        let open_fee = (qty * (perp_types::fc_open_fee_p(&fee_config) as u64)) / 10000;
        assert!(amount_in > open_fee, perp_types::e_insufficient_margin());
        let net_margin = amount_in - open_fee;

        // Deposit margin
        perp_vault::deposit_margin(vault, payment);

        // Record broker commission
        let oct_symbol = std::string::utf8(b"OCT");
        let (_commission, actual_broker_id, _dao_amount, _lp_amount) = perp_broker::record_commission(
            broker_manager,
            oct_symbol,
            open_fee,
            broker_id,
            ctx
        );

        // Collect fees
        perp_vault::collect_fees(vault, open_fee);

        // Calculate liquidation price
        let liq_threshold = perp_config::get_liquidation_threshold(config, pair_base, qty);
        let liquidation_price = calculate_liquidation_price(is_long, entry_price, net_margin, qty, liq_threshold);

        // Get holding fee rate
        let holding_fee_rate = perp_config::get_holding_fee_rate(config, pair_base, is_long);

        // Get accumulated funding fee
        let long_acc_funding = if (table::contains(&storage.long_acc_funding_fee, pair_base)) {
            *table::borrow(&storage.long_acc_funding_fee, pair_base)
        } else {
            table::add(&mut storage.long_acc_funding_fee, pair_base, 0);
            0
        };

        // Create position (default to isolated margin)
        let position = Position {
            id: object::new(ctx),
            trader: user,
            pair_base,
            margin: net_margin,
            qty,
            leverage,
            is_long,
            entry_price,
            liquidation_price,
            opened_at: tx_context::epoch(ctx),
            last_funding_update: tx_context::epoch(ctx),
            stop_loss,
            take_profit,
            holding_fee_rate,
            broker_id: actual_broker_id,
            long_acc_funding_fee_per_share: long_acc_funding,
            margin_mode: perp_types::margin_isolated(), // Default to isolated
        };

        let position_id = object::id(&position);

        // Update OI
        perp_config::increase_oi(config, pair_base, is_long, (notional_usd as u64));

        // Reserve liquidity
        perp_vault::reserve(vault, qty);

        // Update position info
        update_position_info(storage, pair_base, is_long, qty, true);

        // Track user positions
        if (!table::contains(&storage.user_positions, user)) {
            table::add(&mut storage.user_positions, user, vector::empty());
        };
        let user_pos = table::borrow_mut(&mut storage.user_positions, user);
        vector::push_back(user_pos, position_id);

        event::emit(PositionOpened {
            position_id,
            trader: user,
            pair_base,
            margin: net_margin,
            qty,
            leverage,
            is_long,
            entry_price,
            liquidation_price,
        });

        transfer::public_transfer(position, user);
    }

    // ============================================
    // CLOSE POSITION
    // ============================================

    public entry fun close_position(
        storage: &mut TradingStorage,
        config: &mut ConfigManager,
        vault: &mut Vault,
        broker_manager: &mut BrokerManager,
        oracle: &Oracle,
        position: Position,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let trader = tx_context::sender(ctx);
        assert!(position.trader == trader, perp_types::e_not_position_owner());

        close_position_internal(storage, config, vault, broker_manager, oracle, position, clock, ctx);
    }

    fun close_position_internal(
        storage: &mut TradingStorage,
        config: &mut ConfigManager,
        vault: &mut Vault,
        broker_manager: &mut BrokerManager,
        oracle: &Oracle,
        position: Position,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_price = perp_oracle::get_price(oracle, position.pair_base, clock);

        // Calculate PnL
        let (pnl, is_profit) = calculate_pnl(
            position.is_long,
            position.entry_price,
            current_price,
            position.qty
        );

        // Calculate fees
        let fee_config = perp_config::get_fee_config(config, position.pair_base);
        let close_fee = calculate_close_fee(&fee_config, position.qty, pnl, is_profit);

        // Calculate funding fee
        let funding_fee = calculate_funding_fee(storage, &position, current_price);

        // Calculate holding fee
        let current_block = tx_context::epoch(ctx);
        let holding_fee = calculate_holding_fee(&position, current_block);

        let total_fees = close_fee + funding_fee + holding_fee;

        // Calculate payout
        let payout = if (is_profit) {
            let gross = position.margin + pnl;
            if (gross > total_fees) { gross - total_fees } else { 0 }
        } else {
            if (position.margin > pnl + total_fees) {
                position.margin - pnl - total_fees
            } else { 0 }
        };

        // Record broker commission on close fee
        let oct_symbol = std::string::utf8(b"OCT");
        perp_broker::record_commission(broker_manager, oct_symbol, close_fee, position.broker_id, ctx);

        // Collect fees
        perp_vault::collect_fees(vault, total_fees);

        // Release reserved liquidity
        perp_vault::release(vault, position.qty);

        // Update OI
        let notional_usd = (position.qty as u128) * (current_price as u128) / (perp_types::price_precision() as u128);
        perp_config::decrease_oi(config, position.pair_base, position.is_long, (notional_usd as u64));

        // Update position info
        update_position_info(storage, position.pair_base, position.is_long, position.qty, false);

        let position_id = object::id(&position);
        let trader = position.trader;
        let pair_base = position.pair_base;

        // Pay out to trader
        if (payout > 0) {
            let payout_coin = perp_vault::withdraw_margin(vault, payout, ctx);
            transfer::public_transfer(payout_coin, trader);
        };

        event::emit(PositionClosed {
            position_id,
            trader,
            pair_base,
            pnl,
            is_profit,
            close_fee,
            funding_fee,
        });

        // Delete position
        let Position {
            id,
            trader: _,
            pair_base: _,
            margin: _,
            qty: _,
            leverage: _,
            is_long: _,
            entry_price: _,
            liquidation_price: _,
            opened_at: _,
            last_funding_update: _,
            stop_loss: _,
            take_profit: _,
            holding_fee_rate: _,
            broker_id: _,
            long_acc_funding_fee_per_share: _,
            margin_mode: _,
        } = position;
        object::delete(id);
    }

    // ============================================
    // LIQUIDATION
    // ============================================

    public entry fun liquidate_position(
        storage: &mut TradingStorage,
        config: &mut ConfigManager,
        vault: &mut Vault,
        broker_manager: &mut BrokerManager,
        oracle: &Oracle,
        position: Position,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let liquidator = tx_context::sender(ctx);
        assert!(liquidator != position.trader, perp_types::e_not_position_owner());

        let current_price = perp_oracle::get_price(oracle, position.pair_base, clock);

        // Check if liquidatable
        assert!(is_liquidatable(&position, current_price), perp_types::e_position_not_liquidatable());

        // Liquidation reward: 5% of collateral, 1% to liquidator
        let liquidation_penalty = (position.margin * 500) / 10000; // 5%
        let liquidator_reward = (position.margin * 100) / 10000;   // 1%
        let pool_fee = liquidation_penalty - liquidator_reward;

        // Release reserved liquidity
        perp_vault::release(vault, position.qty);

        // Update OI
        let notional_usd = (position.qty as u128) * (current_price as u128) / (perp_types::price_precision() as u128);
        perp_config::decrease_oi(config, position.pair_base, position.is_long, (notional_usd as u64));

        // Update position info
        update_position_info(storage, position.pair_base, position.is_long, position.qty, false);

        // Collect pool fee
        perp_vault::collect_fees(vault, pool_fee);

        // Pay liquidator
        if (liquidator_reward > 0) {
            let reward_coin = perp_vault::withdraw_margin(vault, liquidator_reward, ctx);
            transfer::public_transfer(reward_coin, liquidator);
        };

        let position_id = object::id(&position);
        let trader = position.trader;
        let pair_base = position.pair_base;
        let collateral_seized = position.margin;

        event::emit(PositionLiquidated {
            position_id,
            trader,
            liquidator,
            pair_base,
            collateral_seized,
            liquidator_reward,
        });

        // Delete position
        let Position {
            id,
            trader: _,
            pair_base: _,
            margin: _,
            qty: _,
            leverage: _,
            is_long: _,
            entry_price: _,
            liquidation_price: _,
            opened_at: _,
            last_funding_update: _,
            stop_loss: _,
            take_profit: _,
            holding_fee_rate: _,
            broker_id: _,
            long_acc_funding_fee_per_share: _,
            margin_mode: _,
        } = position;
        object::delete(id);
    }

    // ============================================
    // POSITION MANAGEMENT
    // ============================================

    public entry fun update_tp_sl(
        position: &mut Position,
        take_profit: u64,
        stop_loss: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == position.trader, perp_types::e_not_position_owner());

        // Validate TP/SL
        if (take_profit > 0) {
            if (position.is_long) {
                assert!(take_profit > position.entry_price, perp_types::e_invalid_take_profit());
            } else {
                assert!(take_profit < position.entry_price, perp_types::e_invalid_take_profit());
            };
        };

        if (stop_loss > 0) {
            if (position.is_long) {
                assert!(stop_loss < position.entry_price, perp_types::e_invalid_stop_loss());
            } else {
                assert!(stop_loss > position.entry_price, perp_types::e_invalid_stop_loss());
            };
        };

        position.take_profit = take_profit;
        position.stop_loss = stop_loss;

        event::emit(TpSlUpdated {
            position_id: object::id(position),
            stop_loss,
            take_profit,
        });
    }

    public entry fun add_margin(
        vault: &mut Vault,
        position: &mut Position,
        payment: Coin<OCT>,
        config: &ConfigManager,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == position.trader, perp_types::e_not_position_owner());

        let amount = coin::value(&payment);
        assert!(amount > 0, perp_types::e_insufficient_margin());

        // Deposit margin
        perp_vault::deposit_margin(vault, payment);

        // Update position
        position.margin = position.margin + amount;

        // Recalculate liquidation price
        let liq_threshold = perp_config::get_liquidation_threshold(config, position.pair_base, position.qty);
        position.liquidation_price = calculate_liquidation_price(
            position.is_long,
            position.entry_price,
            position.margin,
            position.qty,
            liq_threshold
        );

        event::emit(MarginAdded {
            position_id: object::id(position),
            amount,
            new_margin: position.margin,
        });
    }

    // ============================================
    // BATCH OPERATIONS
    // ============================================

    public entry fun batch_close_positions(
        storage: &mut TradingStorage,
        config: &mut ConfigManager,
        vault: &mut Vault,
        broker_manager: &mut BrokerManager,
        oracle: &Oracle,
        mut positions: vector<Position>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let trader = tx_context::sender(ctx);
        let len = vector::length(&positions);
        let mut i = 0;

        while (i < len) {
            let position = vector::pop_back(&mut positions);
            assert!(position.trader == trader, perp_types::e_not_position_owner());
            close_position_internal(storage, config, vault, broker_manager, oracle, position, clock, ctx);
            i = i + 1;
        };

        vector::destroy_empty(positions);
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    fun calculate_pnl(
        is_long: bool,
        entry_price: u64,
        current_price: u64,
        qty: u64
    ): (u64, bool) {
        if (is_long) {
            if (current_price >= entry_price) {
                let pnl = (qty * (current_price - entry_price)) / entry_price;
                (pnl, true)
            } else {
                let pnl = (qty * (entry_price - current_price)) / entry_price;
                (pnl, false)
            }
        } else {
            if (entry_price >= current_price) {
                let pnl = (qty * (entry_price - current_price)) / entry_price;
                (pnl, true)
            } else {
                let pnl = (qty * (current_price - entry_price)) / entry_price;
                (pnl, false)
            }
        }
    }

    fun calculate_liquidation_price(
        is_long: bool,
        entry_price: u64,
        margin: u64,
        qty: u64,
        liq_threshold_bps: u16
    ): u64 {
        let threshold_margin = (margin * (liq_threshold_bps as u64)) / 10000;
        let price_move_bps = (threshold_margin * 10000) / qty;

        if (is_long) {
            // Long: liquidate when price drops
            if (entry_price > (entry_price * price_move_bps) / 10000) {
                entry_price - (entry_price * price_move_bps) / 10000
            } else {
                0
            }
        } else {
            // Short: liquidate when price rises
            entry_price + (entry_price * price_move_bps) / 10000
        }
    }

    fun calculate_close_fee(
        fee_config: &FeeConfig,
        qty: u64,
        pnl: u64,
        is_profit: bool
    ): u64 {
        let share_p = perp_types::fc_share_p(fee_config);
        let min_close_fee_p = perp_types::fc_min_close_fee_p(fee_config);

        if (share_p > 0 && min_close_fee_p > 0 && is_profit) {
            // PnL-based fee: max(pnl * share_p, qty * min_close_fee_p)
            let pnl_based = (pnl * (share_p as u64)) / 100000;
            let min_fee = (qty * (min_close_fee_p as u64)) / 100000;
            if (pnl_based > min_fee) { pnl_based } else { min_fee }
        } else {
            // Flat percentage fee
            (qty * (perp_types::fc_close_fee_p(fee_config) as u64)) / 10000
        }
    }

    fun calculate_funding_fee(
        storage: &TradingStorage,
        position: &Position,
        current_price: u64
    ): u64 {
        let current_acc = if (table::contains(&storage.long_acc_funding_fee, position.pair_base)) {
            *table::borrow(&storage.long_acc_funding_fee, position.pair_base)
        } else {
            0
        };

        let diff = if (current_acc >= position.long_acc_funding_fee_per_share) {
            current_acc - position.long_acc_funding_fee_per_share
        } else {
            position.long_acc_funding_fee_per_share - current_acc
        };

        // Simplified funding fee calculation
        let notional = (position.qty as u128) * (current_price as u128) / (perp_types::price_precision() as u128);
        let fee = (notional * diff) / perp_types::funding_precision();

        (fee as u64)
    }

    fun calculate_holding_fee(position: &Position, current_block: u64): u64 {
        if (position.holding_fee_rate == 0 || position.opened_at >= current_block) {
            return 0
        };

        let blocks_held = current_block - position.opened_at;
        (position.qty * blocks_held * position.holding_fee_rate) / perp_types::holding_fee_precision()
    }

    fun is_liquidatable(position: &Position, current_price: u64): bool {
        if (position.is_long) {
            current_price <= position.liquidation_price
        } else {
            current_price >= position.liquidation_price
        }
    }

    fun update_position_info(
        storage: &mut TradingStorage,
        pair_base: String,
        is_long: bool,
        qty: u64,
        is_increase: bool
    ) {
        if (!table::contains(&storage.position_info, pair_base)) {
            table::add(&mut storage.position_info, pair_base, PositionInfo {
                long_qty: 0,
                short_qty: 0,
                last_funding_block: 0,
            });
        };

        let info = table::borrow_mut(&mut storage.position_info, pair_base);

        if (is_increase) {
            if (is_long) {
                info.long_qty = info.long_qty + qty;
            } else {
                info.short_qty = info.short_qty + qty;
            };
        } else {
            if (is_long) {
                info.long_qty = if (info.long_qty >= qty) { info.long_qty - qty } else { 0 };
            } else {
                info.short_qty = if (info.short_qty >= qty) { info.short_qty - qty } else { 0 };
            };
        };
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    public fun get_position_pnl(
        position: &Position,
        current_price: u64
    ): (u64, bool) {
        calculate_pnl(position.is_long, position.entry_price, current_price, position.qty)
    }

    public fun get_position_value(
        position: &Position,
        current_price: u64
    ): u64 {
        let (pnl, is_profit) = calculate_pnl(position.is_long, position.entry_price, current_price, position.qty);

        if (is_profit) {
            position.margin + pnl
        } else {
            if (position.margin > pnl) { position.margin - pnl } else { 0 }
        }
    }

    public fun check_liquidatable(position: &Position, current_price: u64): bool {
        is_liquidatable(position, current_price)
    }

    public fun get_position_info(storage: &TradingStorage, pair_base: String): (u64, u64) {
        if (table::contains(&storage.position_info, pair_base)) {
            let info = table::borrow(&storage.position_info, pair_base);
            (info.long_qty, info.short_qty)
        } else {
            (0, 0)
        }
    }

    // Position field accessors
    public fun position_trader(p: &Position): address { p.trader }
    public fun position_pair_base(p: &Position): String { p.pair_base }
    public fun position_margin(p: &Position): u64 { p.margin }
    public fun position_qty(p: &Position): u64 { p.qty }
    public fun position_leverage(p: &Position): u64 { p.leverage }
    public fun position_is_long(p: &Position): bool { p.is_long }
    public fun position_entry_price(p: &Position): u64 { p.entry_price }
    public fun position_liquidation_price(p: &Position): u64 { p.liquidation_price }
    public fun position_stop_loss(p: &Position): u64 { p.stop_loss }
    public fun position_take_profit(p: &Position): u64 { p.take_profit }
}
