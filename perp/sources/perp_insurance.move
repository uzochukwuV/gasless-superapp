/// Insurance Fund for covering bad debt from liquidations
module perp::perp_insurance {
    use one::object::{UID, ID};
    use one::tx_context::TxContext;
    use one::balance::{Self, Balance};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::clock::Clock;
    use one::event;
    use one::table::{Self, Table};
    use std::string::String;
    use perp::perp_types;

    // ============================================
    // CONSTANTS
    // ============================================

    /// Default contribution rate from liquidation penalties (50%)
    const DEFAULT_LIQUIDATION_CONTRIBUTION_BPS: u64 = 5000;
    /// Maximum insurance fund utilization per liquidation (20%)
    const MAX_UTILIZATION_PER_LIQUIDATION_BPS: u64 = 2000;

    // ============================================
    // STRUCTS
    // ============================================

    /// Insurance fund state
    public struct InsuranceFund has key {
        id: UID,
        admin: address,
        /// Main insurance balance
        balance: Balance<OCT>,
        /// Total deposits ever
        total_deposits: u64,
        /// Total payouts ever (bad debt covered)
        total_payouts: u64,
        /// Contribution rate from liquidation penalties (bps)
        liquidation_contribution_bps: u64,
        /// Max utilization per single liquidation (bps)
        max_utilization_bps: u64,
        /// Per-pair insurance tracking
        pair_payouts: Table<String, u64>,
        /// Is fund accepting deposits
        deposits_enabled: bool,
        /// Is fund paying out
        payouts_enabled: bool,
        /// ADL trigger threshold - if fund < this, trigger ADL
        adl_threshold: u64,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct InsuranceFundCreated has copy, drop {
        fund_id: ID,
        admin: address,
    }

    public struct InsuranceDeposit has copy, drop {
        depositor: address,
        amount: u64,
        source: u8, // 0 = direct, 1 = liquidation, 2 = fees
        total_balance: u64,
    }

    public struct InsurancePayout has copy, drop {
        pair: String,
        amount: u64,
        bad_debt: u64,
        remaining_balance: u64,
    }

    public struct ADLTriggered has copy, drop {
        pair: String,
        insurance_balance: u64,
        threshold: u64,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let fund = InsuranceFund {
            id: object::new(ctx),
            admin,
            balance: balance::zero(),
            total_deposits: 0,
            total_payouts: 0,
            liquidation_contribution_bps: DEFAULT_LIQUIDATION_CONTRIBUTION_BPS,
            max_utilization_bps: MAX_UTILIZATION_PER_LIQUIDATION_BPS,
            pair_payouts: table::new(ctx),
            deposits_enabled: true,
            payouts_enabled: true,
            adl_threshold: 0, // Will be set by admin
        };

        event::emit(InsuranceFundCreated {
            fund_id: object::id(&fund),
            admin,
        });

        transfer::share_object(fund);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ============================================
    // DEPOSIT FUNCTIONS
    // ============================================

    /// Direct deposit to insurance fund
    public entry fun deposit(
        fund: &mut InsuranceFund,
        payment: Coin<OCT>,
        ctx: &mut TxContext
    ) {
        assert!(fund.deposits_enabled, perp_types::e_insurance_paused());

        let amount = coin::value(&payment);
        balance::join(&mut fund.balance, coin::into_balance(payment));
        fund.total_deposits = fund.total_deposits + amount;

        event::emit(InsuranceDeposit {
            depositor: tx_context::sender(ctx),
            amount,
            source: 0, // direct
            total_balance: balance::value(&fund.balance),
        });
    }

    /// Deposit from liquidation penalty (called by trading module)
    public fun deposit_from_liquidation(
        fund: &mut InsuranceFund,
        payment: Coin<OCT>,
    ) {
        let amount = coin::value(&payment);
        balance::join(&mut fund.balance, coin::into_balance(payment));
        fund.total_deposits = fund.total_deposits + amount;

        event::emit(InsuranceDeposit {
            depositor: @0x0, // System
            amount,
            source: 1, // liquidation
            total_balance: balance::value(&fund.balance),
        });
    }

    /// Deposit from fees (called by fee manager)
    public fun deposit_from_fees(
        fund: &mut InsuranceFund,
        payment: Coin<OCT>,
    ) {
        let amount = coin::value(&payment);
        balance::join(&mut fund.balance, coin::into_balance(payment));
        fund.total_deposits = fund.total_deposits + amount;

        event::emit(InsuranceDeposit {
            depositor: @0x0, // System
            amount,
            source: 2, // fees
            total_balance: balance::value(&fund.balance),
        });
    }

    // ============================================
    // PAYOUT FUNCTIONS
    // ============================================

    /// Cover bad debt from a liquidation
    /// Returns: amount actually covered (may be less than requested if fund insufficient)
    public fun cover_bad_debt(
        fund: &mut InsuranceFund,
        pair: String,
        bad_debt: u64,
        ctx: &mut TxContext
    ): Coin<OCT> {
        assert!(fund.payouts_enabled, perp_types::e_insurance_paused());

        let fund_balance = balance::value(&fund.balance);

        // Calculate max we can pay (limited by utilization cap)
        let max_payout = (fund_balance * fund.max_utilization_bps) / 10000;
        let payout_amount = if (bad_debt <= max_payout) {
            bad_debt
        } else {
            max_payout
        };

        // Track per-pair payouts
        if (table::contains(&fund.pair_payouts, pair)) {
            let current = *table::borrow(&fund.pair_payouts, pair);
            table::remove(&mut fund.pair_payouts, pair);
            table::add(&mut fund.pair_payouts, pair, current + payout_amount);
        } else {
            table::add(&mut fund.pair_payouts, pair, payout_amount);
        };

        fund.total_payouts = fund.total_payouts + payout_amount;

        event::emit(InsurancePayout {
            pair,
            amount: payout_amount,
            bad_debt,
            remaining_balance: fund_balance - payout_amount,
        });

        coin::from_balance(balance::split(&mut fund.balance, payout_amount), ctx)
    }

    /// Check if ADL should be triggered
    public fun should_trigger_adl(fund: &InsuranceFund, bad_debt: u64): bool {
        let fund_balance = balance::value(&fund.balance);

        // ADL triggers if:
        // 1. Bad debt exceeds what insurance can cover
        // 2. Fund balance falls below threshold
        if (fund_balance < fund.adl_threshold) {
            return true
        };

        let max_payout = (fund_balance * fund.max_utilization_bps) / 10000;
        bad_debt > max_payout
    }

    /// Emit ADL trigger event
    public fun emit_adl_trigger(fund: &InsuranceFund, pair: String) {
        event::emit(ADLTriggered {
            pair,
            insurance_balance: balance::value(&fund.balance),
            threshold: fund.adl_threshold,
        });
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    public entry fun set_liquidation_contribution(
        fund: &mut InsuranceFund,
        bps: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == fund.admin, perp_types::e_not_admin());
        assert!(bps <= 10000, perp_types::e_invalid_leverage_tier());
        fund.liquidation_contribution_bps = bps;
    }

    public entry fun set_max_utilization(
        fund: &mut InsuranceFund,
        bps: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == fund.admin, perp_types::e_not_admin());
        assert!(bps <= 10000, perp_types::e_invalid_leverage_tier());
        fund.max_utilization_bps = bps;
    }

    public entry fun set_adl_threshold(
        fund: &mut InsuranceFund,
        threshold: u64,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == fund.admin, perp_types::e_not_admin());
        fund.adl_threshold = threshold;
    }

    public entry fun set_deposits_enabled(
        fund: &mut InsuranceFund,
        enabled: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == fund.admin, perp_types::e_not_admin());
        fund.deposits_enabled = enabled;
    }

    public entry fun set_payouts_enabled(
        fund: &mut InsuranceFund,
        enabled: bool,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == fund.admin, perp_types::e_not_admin());
        fund.payouts_enabled = enabled;
    }

    /// Emergency withdraw (admin only, for migration)
    public entry fun emergency_withdraw(
        fund: &mut InsuranceFund,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == fund.admin, perp_types::e_not_admin());
        assert!(balance::value(&fund.balance) >= amount, perp_types::e_insurance_insufficient());

        let withdrawal = coin::from_balance(balance::split(&mut fund.balance, amount), ctx);
        transfer::public_transfer(withdrawal, fund.admin);
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    public fun balance(fund: &InsuranceFund): u64 {
        balance::value(&fund.balance)
    }

    public fun total_deposits(fund: &InsuranceFund): u64 {
        fund.total_deposits
    }

    public fun total_payouts(fund: &InsuranceFund): u64 {
        fund.total_payouts
    }

    public fun liquidation_contribution_bps(fund: &InsuranceFund): u64 {
        fund.liquidation_contribution_bps
    }

    public fun max_utilization_bps(fund: &InsuranceFund): u64 {
        fund.max_utilization_bps
    }

    public fun adl_threshold(fund: &InsuranceFund): u64 {
        fund.adl_threshold
    }

    public fun pair_payout(fund: &InsuranceFund, pair: String): u64 {
        if (table::contains(&fund.pair_payouts, pair)) {
            *table::borrow(&fund.pair_payouts, pair)
        } else {
            0
        }
    }

    public fun is_healthy(fund: &InsuranceFund): bool {
        balance::value(&fund.balance) >= fund.adl_threshold
    }
}
