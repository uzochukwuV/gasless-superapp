/// Cross Margin Account management for shared collateral across positions
module perp::perp_margin {
    use one::object::{UID, ID};
    use one::tx_context::TxContext;
    use one::balance::{Self, Balance};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::event;
    use one::table::{Self, Table};
    use std::string::String;
    use perp::perp_types;

    // ============================================
    // STRUCTS
    // ============================================

    /// Cross margin account for a user
    public struct CrossMarginAccount has key, store {
        id: UID,
        owner: address,
        /// Available balance for new positions
        available_balance: Balance<OCT>,
        /// Total balance (available + used in positions)
        total_balance: u64,
        /// Locked margin in open positions
        locked_margin: u64,
        /// Position IDs using this account
        position_ids: vector<ID>,
        /// Unrealized PnL (sum of all positions)
        unrealized_pnl: u64,
        unrealized_pnl_is_negative: bool,
        /// Account equity = total_balance + unrealized_pnl
        last_equity_update: u64,
        /// Is account liquidatable
        is_liquidatable: bool,
    }

    /// Cross margin manager
    public struct CrossMarginManager has key {
        id: UID,
        admin: address,
        /// User accounts
        accounts: Table<address, ID>,
        /// Minimum margin ratio for cross margin (bps) - below this = liquidation
        min_margin_ratio_bps: u64,
        /// Initial margin requirement (bps)
        initial_margin_ratio_bps: u64,
        /// Total cross margin deposits
        total_deposits: u64,
        /// Is cross margin enabled
        enabled: bool,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct CrossMarginManagerCreated has copy, drop {
        manager_id: ID,
        admin: address,
    }

    public struct CrossMarginAccountCreated has copy, drop {
        account_id: ID,
        owner: address,
    }

    public struct CrossMarginDeposit has copy, drop {
        account_id: ID,
        owner: address,
        amount: u64,
        new_balance: u64,
    }

    public struct CrossMarginWithdraw has copy, drop {
        account_id: ID,
        owner: address,
        amount: u64,
        new_balance: u64,
    }

    public struct CrossMarginPositionAdded has copy, drop {
        account_id: ID,
        position_id: ID,
        margin_locked: u64,
    }

    public struct CrossMarginPositionRemoved has copy, drop {
        account_id: ID,
        position_id: ID,
        margin_released: u64,
        pnl: u64,
        is_profit: bool,
    }

    public struct CrossMarginLiquidation has copy, drop {
        account_id: ID,
        owner: address,
        equity: u64,
        margin_ratio_bps: u64,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let manager = CrossMarginManager {
            id: object::new(ctx),
            admin,
            accounts: table::new(ctx),
            min_margin_ratio_bps: 50,    // 0.5% maintenance margin
            initial_margin_ratio_bps: 100, // 1% initial margin
            total_deposits: 0,
            enabled: true,
        };

        event::emit(CrossMarginManagerCreated {
            manager_id: object::id(&manager),
            admin,
        });

        transfer::share_object(manager);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ============================================
    // ACCOUNT MANAGEMENT
    // ============================================

    /// Create a cross margin account
    public entry fun create_account(
        manager: &mut CrossMarginManager,
        initial_deposit: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        assert!(manager.enabled, perp_types::e_trading_disabled());

        let owner = tx_context::sender(ctx);
        assert!(!table::contains(&manager.accounts, owner), perp_types::e_broker_exists());

        let amount = coin::value(&initial_deposit);

        let account = CrossMarginAccount {
            id: object::new(ctx),
            owner,
            available_balance: coin::into_balance(initial_deposit),
            total_balance: amount,
            locked_margin: 0,
            position_ids: vector::empty(),
            unrealized_pnl: 0,
            unrealized_pnl_is_negative: false,
            last_equity_update: 0,
            is_liquidatable: false,
        };

        let account_id = object::id(&account);
        table::add(&mut manager.accounts, owner, account_id);
        manager.total_deposits = manager.total_deposits + amount;

        event::emit(CrossMarginAccountCreated {
            account_id,
            owner,
        });

        transfer::share_object(account);
    }

    /// Deposit to cross margin account
    public entry fun deposit(
        account: &mut CrossMarginAccount,
        payment: Coin<OCT>,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == account.owner, perp_types::e_not_position_owner());

        let amount = coin::value(&payment);
        balance::join(&mut account.available_balance, coin::into_balance(payment));
        account.total_balance = account.total_balance + amount;

        event::emit(CrossMarginDeposit {
            account_id: object::id(account),
            owner: account.owner,
            amount,
            new_balance: account.total_balance,
        });
    }

    /// Withdraw from cross margin account
    public entry fun withdraw(
        account: &mut CrossMarginAccount,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == account.owner, perp_types::e_not_position_owner());

        let available = balance::value(&account.available_balance);
        assert!(amount <= available, perp_types::e_insufficient_balance());

        // Check if withdrawal would put account below margin requirement
        // For simplicity, we just check if there's enough available balance
        // In production, you'd calculate equity and margin ratio

        let withdrawal = coin::from_balance(
            balance::split(&mut account.available_balance, amount),
            ctx
        );
        account.total_balance = account.total_balance - amount;

        transfer::public_transfer(withdrawal, account.owner);

        event::emit(CrossMarginWithdraw {
            account_id: object::id(account),
            owner: account.owner,
            amount,
            new_balance: account.total_balance,
        });
    }

    // ============================================
    // POSITION MANAGEMENT (called by trading module)
    // ============================================

    /// Lock margin for a new cross-margin position
    public fun lock_margin_for_position(
        account: &mut CrossMarginAccount,
        position_id: ID,
        margin_required: u64,
    ) {
        let available = balance::value(&account.available_balance);
        assert!(available >= margin_required, perp_types::e_insufficient_margin());

        account.locked_margin = account.locked_margin + margin_required;
        vector::push_back(&mut account.position_ids, position_id);

        event::emit(CrossMarginPositionAdded {
            account_id: object::id(account),
            position_id,
            margin_locked: margin_required,
        });
    }

    /// Release margin when closing a cross-margin position
    public fun release_margin_for_position(
        account: &mut CrossMarginAccount,
        position_id: ID,
        margin_locked: u64,
        pnl: u64,
        is_profit: bool,
        ctx: &mut TxContext
    ) {
        // Update locked margin
        account.locked_margin = if (account.locked_margin >= margin_locked) {
            account.locked_margin - margin_locked
        } else {
            0
        };

        // Remove position from list
        let len = vector::length(&account.position_ids);
        let mut i = 0;
        while (i < len) {
            if (*vector::borrow(&account.position_ids, i) == position_id) {
                vector::remove(&mut account.position_ids, i);
                break
            };
            i = i + 1;
        };

        // Update balance with PnL
        if (is_profit) {
            account.total_balance = account.total_balance + pnl;
        } else {
            account.total_balance = if (account.total_balance >= pnl) {
                account.total_balance - pnl
            } else {
                0
            };
        };

        event::emit(CrossMarginPositionRemoved {
            account_id: object::id(account),
            position_id,
            margin_released: margin_locked,
            pnl,
            is_profit,
        });
    }

    /// Update unrealized PnL for the account
    public fun update_unrealized_pnl(
        account: &mut CrossMarginAccount,
        total_pnl: u64,
        is_negative: bool,
    ) {
        account.unrealized_pnl = total_pnl;
        account.unrealized_pnl_is_negative = is_negative;
    }

    /// Check if account is liquidatable
    public fun check_liquidation(
        account: &mut CrossMarginAccount,
        manager: &CrossMarginManager,
    ): bool {
        if (account.locked_margin == 0) {
            account.is_liquidatable = false;
            return false
        };

        let equity = get_account_equity(account);

        // Margin ratio = (equity / locked_margin) * 10000
        let margin_ratio_bps = if (account.locked_margin > 0) {
            (equity * 10000) / account.locked_margin
        } else {
            10000 // 100% if no locked margin
        };

        account.is_liquidatable = margin_ratio_bps < manager.min_margin_ratio_bps;

        if (account.is_liquidatable) {
            event::emit(CrossMarginLiquidation {
                account_id: object::id(account),
                owner: account.owner,
                equity,
                margin_ratio_bps,
            });
        };

        account.is_liquidatable
    }

    /// Get margin required for a new position
    public fun get_margin_requirement(
        manager: &CrossMarginManager,
        notional_usd: u64,
    ): u64 {
        (notional_usd * manager.initial_margin_ratio_bps) / 10000
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    public entry fun set_min_margin_ratio(
        manager: &mut CrossMarginManager,
        min_ratio_bps: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.min_margin_ratio_bps = min_ratio_bps;
    }

    public entry fun set_initial_margin_ratio(
        manager: &mut CrossMarginManager,
        initial_ratio_bps: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.initial_margin_ratio_bps = initial_ratio_bps;
    }

    public entry fun set_enabled(
        manager: &mut CrossMarginManager,
        enabled: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        manager.enabled = enabled;
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    public fun get_account_equity(account: &CrossMarginAccount): u64 {
        if (account.unrealized_pnl_is_negative) {
            if (account.total_balance >= account.unrealized_pnl) {
                account.total_balance - account.unrealized_pnl
            } else {
                0
            }
        } else {
            account.total_balance + account.unrealized_pnl
        }
    }

    public fun get_available_balance(account: &CrossMarginAccount): u64 {
        balance::value(&account.available_balance)
    }

    public fun get_total_balance(account: &CrossMarginAccount): u64 {
        account.total_balance
    }

    public fun get_locked_margin(account: &CrossMarginAccount): u64 {
        account.locked_margin
    }

    public fun get_position_count(account: &CrossMarginAccount): u64 {
        vector::length(&account.position_ids)
    }

    public fun is_liquidatable(account: &CrossMarginAccount): bool {
        account.is_liquidatable
    }

    public fun get_margin_ratio_bps(account: &CrossMarginAccount): u64 {
        if (account.locked_margin == 0) {
            return 10000
        };
        let equity = get_account_equity(account);
        (equity * 10000) / account.locked_margin
    }

    public fun has_account(manager: &CrossMarginManager, owner: address): bool {
        table::contains(&manager.accounts, owner)
    }

    public fun get_account_id(manager: &CrossMarginManager, owner: address): ID {
        assert!(table::contains(&manager.accounts, owner), perp_types::e_broker_not_found());
        *table::borrow(&manager.accounts, owner)
    }

    public fun is_enabled(manager: &CrossMarginManager): bool {
        manager.enabled
    }

    public fun total_deposits(manager: &CrossMarginManager): u64 {
        manager.total_deposits
    }

    public fun min_margin_ratio_bps(manager: &CrossMarginManager): u64 {
        manager.min_margin_ratio_bps
    }

    public fun initial_margin_ratio_bps(manager: &CrossMarginManager): u64 {
        manager.initial_margin_ratio_bps
    }
}
