/// Liquidity vault and margin token management (based on Astex IVault)
module perp::perp_vault {
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
    use perp::perp_types;

    // ============================================
    // CONSTANTS
    // ============================================

    const INITIAL_LP_PRICE: u64 = 1_000_000_000_000; // 1e12 = $1.00

    // ============================================
    // STRUCTS
    // ============================================

    /// Margin token info (for multi-collateral support)
    public struct MarginToken has store, copy, drop {
        symbol: String,
        decimals: u8,
        price: u64,             // USD price (1e10)
        switch_on: bool,        // Is this token enabled
        weight: u16,            // Portfolio weight (bps)
    }

    /// LP token holder info
    public struct LPHolder has store {
        balance: u64,
        last_deposit_time: u64,
    }

    /// Main liquidity vault
    public struct Vault has key {
        id: UID,
        admin: address,
        /// Main liquidity pool (OCT)
        liquidity: Balance<OCT>,
        /// Total LP tokens supply
        lp_supply: u64,
        /// LP holders
        lp_holders: Table<address, LPHolder>,
        /// Reserved for open positions (cannot withdraw)
        reserved: u64,
        /// Total fees collected
        total_fees: u64,
        /// Margin tokens config
        margin_tokens: Table<String, MarginToken>,
        /// Margin token list
        margin_token_list: vector<String>,
        /// Open trade margin amounts per token
        open_trade_amounts: Table<String, u64>,
        /// Pending trade margin amounts per token
        pending_trade_amounts: Table<String, u64>,
        /// Withdrawal lock period (ms)
        withdrawal_lock_ms: u64,
        /// Is vault paused
        is_paused: bool,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct VaultCreated has copy, drop {
        vault_id: ID,
        admin: address,
    }

    public struct LiquidityAdded has copy, drop {
        provider: address,
        amount: u64,
        lp_minted: u64,
        total_liquidity: u64,
    }

    public struct LiquidityRemoved has copy, drop {
        provider: address,
        amount: u64,
        lp_burned: u64,
        total_liquidity: u64,
    }

    public struct MarginTokenAdded has copy, drop {
        symbol: String,
        decimals: u8,
    }

    public struct ReserveIncreased has copy, drop {
        amount: u64,
        total_reserved: u64,
    }

    public struct ReserveDecreased has copy, drop {
        amount: u64,
        total_reserved: u64,
    }

    public struct FeesCollected has copy, drop {
        amount: u64,
        total_fees: u64,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let mut vault = Vault {
            id: object::new(ctx),
            admin,
            liquidity: balance::zero(),
            lp_supply: 0,
            lp_holders: table::new(ctx),
            reserved: 0,
            total_fees: 0,
            margin_tokens: table::new(ctx),
            margin_token_list: vector::empty(),
            open_trade_amounts: table::new(ctx),
            pending_trade_amounts: table::new(ctx),
            withdrawal_lock_ms: 86400000, // 24 hours
            is_paused: false,
        };

        // Add OCT as default margin token
        let oct_token = MarginToken {
            symbol: std::string::utf8(b"OCT"),
            decimals: 9,
            price: 1_000_000_000_000, // $1.00 (placeholder)
            switch_on: true,
            weight: 10000, // 100%
        };
        table::add(&mut vault.margin_tokens, std::string::utf8(b"OCT"), oct_token);
        vector::push_back(&mut vault.margin_token_list, std::string::utf8(b"OCT"));
        table::add(&mut vault.open_trade_amounts, std::string::utf8(b"OCT"), 0);
        table::add(&mut vault.pending_trade_amounts, std::string::utf8(b"OCT"), 0);

        event::emit(VaultCreated {
            vault_id: object::id(&vault),
            admin,
        });

        transfer::share_object(vault);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ============================================
    // LIQUIDITY PROVIDER FUNCTIONS
    // ============================================

    /// Add liquidity to the vault
    public entry fun add_liquidity(
        vault: &mut Vault,
        mut payment: Coin<OCT>,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!vault.is_paused, perp_types::e_trading_disabled());
        assert!(coin::value(&payment) >= amount, perp_types::e_insufficient_balance());

        let provider = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        // Calculate LP tokens to mint
        let lp_to_mint = if (vault.lp_supply == 0) {
            amount // 1:1 for first deposit
        } else {
            let pool_value = balance::value(&vault.liquidity);
            ((amount as u128) * (vault.lp_supply as u128) / (pool_value as u128) as u64)
        };

        // Split and deposit
        let deposit = coin::split(&mut payment, amount, ctx);
        balance::join(&mut vault.liquidity, coin::into_balance(deposit));

        // Mint LP tokens
        vault.lp_supply = vault.lp_supply + lp_to_mint;

        // Update holder
        if (table::contains(&vault.lp_holders, provider)) {
            let holder = table::borrow_mut(&mut vault.lp_holders, provider);
            holder.balance = holder.balance + lp_to_mint;
            holder.last_deposit_time = current_time;
        } else {
            table::add(&mut vault.lp_holders, provider, LPHolder {
                balance: lp_to_mint,
                last_deposit_time: current_time,
            });
        };

        event::emit(LiquidityAdded {
            provider,
            amount,
            lp_minted: lp_to_mint,
            total_liquidity: balance::value(&vault.liquidity),
        });

        // Return change
        transfer::public_transfer(payment, provider);
    }

    /// Remove liquidity from the vault
    public entry fun remove_liquidity(
        vault: &mut Vault,
        lp_amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let provider = tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);

        assert!(table::contains(&vault.lp_holders, provider), perp_types::e_insufficient_balance());

        let holder = table::borrow_mut(&mut vault.lp_holders, provider);
        assert!(holder.balance >= lp_amount, perp_types::e_insufficient_balance());

        // Check lock period
        let time_since_deposit = current_time - holder.last_deposit_time;
        assert!(time_since_deposit >= vault.withdrawal_lock_ms, perp_types::e_withdrawal_locked());

        // Calculate OCT to return
        let pool_value = balance::value(&vault.liquidity);
        let available = pool_value - vault.reserved;
        let oct_to_return = ((lp_amount as u128) * (pool_value as u128) / (vault.lp_supply as u128) as u64);

        assert!(oct_to_return <= available, perp_types::e_insufficient_liquidity());

        // Burn LP tokens
        holder.balance = holder.balance - lp_amount;
        vault.lp_supply = vault.lp_supply - lp_amount;

        // Transfer OCT
        let withdrawal = coin::from_balance(
            balance::split(&mut vault.liquidity, oct_to_return),
            ctx
        );
        transfer::public_transfer(withdrawal, provider);

        event::emit(LiquidityRemoved {
            provider,
            amount: oct_to_return,
            lp_burned: lp_amount,
            total_liquidity: balance::value(&vault.liquidity),
        });
    }

    // ============================================
    // TRADING FUNCTIONS (called by trading module)
    // ============================================

    /// Deposit margin for a trade
    public fun deposit_margin(
        vault: &mut Vault,
        coin: Coin<OCT>,
    ) {
        let amount = coin::value(&coin);
        balance::join(&mut vault.liquidity, coin::into_balance(coin));

        // Track open trade amount
        let oct_symbol = std::string::utf8(b"OCT");
        let current = *table::borrow(&vault.open_trade_amounts, oct_symbol);
        table::remove(&mut vault.open_trade_amounts, oct_symbol);
        table::add(&mut vault.open_trade_amounts, oct_symbol, current + amount);
    }

    /// Withdraw margin/payout for a trade
    public fun withdraw_margin(
        vault: &mut Vault,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<OCT> {
        assert!(balance::value(&vault.liquidity) >= amount, perp_types::e_insufficient_liquidity());

        // Update open trade amount
        let oct_symbol = std::string::utf8(b"OCT");
        let current = *table::borrow(&vault.open_trade_amounts, oct_symbol);
        table::remove(&mut vault.open_trade_amounts, oct_symbol);
        let new_amount = if (current >= amount) { current - amount } else { 0 };
        table::add(&mut vault.open_trade_amounts, oct_symbol, new_amount);

        coin::from_balance(balance::split(&mut vault.liquidity, amount), ctx)
    }

    /// Reserve liquidity for a position
    public fun reserve(vault: &mut Vault, amount: u64) {
        let available = balance::value(&vault.liquidity) - vault.reserved;
        assert!(amount <= available, perp_types::e_insufficient_liquidity());

        vault.reserved = vault.reserved + amount;

        event::emit(ReserveIncreased {
            amount,
            total_reserved: vault.reserved,
        });
    }

    /// Release reserved liquidity
    public fun release(vault: &mut Vault, amount: u64) {
        vault.reserved = if (vault.reserved >= amount) {
            vault.reserved - amount
        } else { 0 };

        event::emit(ReserveDecreased {
            amount,
            total_reserved: vault.reserved,
        });
    }

    /// Collect fees
    public fun collect_fees(vault: &mut Vault, amount: u64) {
        vault.total_fees = vault.total_fees + amount;

        event::emit(FeesCollected {
            amount,
            total_fees: vault.total_fees,
        });
    }

    /// Increase open trade amount tracking
    public fun increase_open_trade_amount(vault: &mut Vault, token: String, amount: u64) {
        if (table::contains(&vault.open_trade_amounts, token)) {
            let current = *table::borrow(&vault.open_trade_amounts, token);
            table::remove(&mut vault.open_trade_amounts, token);
            table::add(&mut vault.open_trade_amounts, token, current + amount);
        } else {
            table::add(&mut vault.open_trade_amounts, token, amount);
        };
    }

    /// Decrease open trade amount tracking
    public fun decrease_open_trade_amount(vault: &mut Vault, token: String, amount: u64) {
        if (table::contains(&vault.open_trade_amounts, token)) {
            let current = *table::borrow(&vault.open_trade_amounts, token);
            table::remove(&mut vault.open_trade_amounts, token);
            let new_amount = if (current >= amount) { current - amount } else { 0 };
            table::add(&mut vault.open_trade_amounts, token, new_amount);
        };
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    public entry fun add_margin_token(
        vault: &mut Vault,
        symbol: String,
        decimals: u8,
        price: u64,
        weight: u16,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, perp_types::e_not_admin());
        assert!(!table::contains(&vault.margin_tokens, symbol), perp_types::e_broker_exists());

        let token = MarginToken {
            symbol,
            decimals,
            price,
            switch_on: true,
            weight,
        };

        table::add(&mut vault.margin_tokens, symbol, token);
        vector::push_back(&mut vault.margin_token_list, symbol);
        table::add(&mut vault.open_trade_amounts, symbol, 0);
        table::add(&mut vault.pending_trade_amounts, symbol, 0);

        event::emit(MarginTokenAdded { symbol, decimals });
    }

    public entry fun update_margin_token_price(
        vault: &mut Vault,
        symbol: String,
        price: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, perp_types::e_not_admin());
        assert!(table::contains(&vault.margin_tokens, symbol), perp_types::e_token_not_supported());

        let token = table::borrow_mut(&mut vault.margin_tokens, symbol);
        token.price = price;
    }

    public entry fun set_margin_token_enabled(
        vault: &mut Vault,
        symbol: String,
        enabled: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, perp_types::e_not_admin());
        assert!(table::contains(&vault.margin_tokens, symbol), perp_types::e_token_not_supported());

        let token = table::borrow_mut(&mut vault.margin_tokens, symbol);
        token.switch_on = enabled;
    }

    public entry fun set_withdrawal_lock(
        vault: &mut Vault,
        lock_ms: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, perp_types::e_not_admin());
        vault.withdrawal_lock_ms = lock_ms;
    }

    public entry fun set_paused(
        vault: &mut Vault,
        paused: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == vault.admin, perp_types::e_not_admin());
        vault.is_paused = paused;
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    public fun get_margin_token(vault: &Vault, symbol: String): MarginToken {
        assert!(table::contains(&vault.margin_tokens, symbol), perp_types::e_token_not_supported());
        *table::borrow(&vault.margin_tokens, symbol)
    }

    public fun total_liquidity(vault: &Vault): u64 {
        balance::value(&vault.liquidity)
    }

    public fun available_liquidity(vault: &Vault): u64 {
        let total = balance::value(&vault.liquidity);
        if (total > vault.reserved) { total - vault.reserved } else { 0 }
    }

    public fun reserved_liquidity(vault: &Vault): u64 {
        vault.reserved
    }

    public fun total_lp_supply(vault: &Vault): u64 {
        vault.lp_supply
    }

    public fun total_fees(vault: &Vault): u64 {
        vault.total_fees
    }

    public fun is_paused(vault: &Vault): bool {
        vault.is_paused
    }

    public fun get_lp_balance(vault: &Vault, addr: address): u64 {
        if (table::contains(&vault.lp_holders, addr)) {
            table::borrow(&vault.lp_holders, addr).balance
        } else {
            0
        }
    }

    public fun get_lp_price(vault: &Vault): u64 {
        if (vault.lp_supply == 0) {
            INITIAL_LP_PRICE
        } else {
            let total = balance::value(&vault.liquidity);
            ((total as u128) * (INITIAL_LP_PRICE as u128) / (vault.lp_supply as u128) as u64)
        }
    }

    public fun get_open_trade_amount(vault: &Vault, token: String): u64 {
        if (table::contains(&vault.open_trade_amounts, token)) {
            *table::borrow(&vault.open_trade_amounts, token)
        } else {
            0
        }
    }
}
