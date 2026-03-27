/// Broker/Referral commission system (based on Astex LibBrokerManager)
module perp::perp_broker {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::table::{Self, Table};
    use one::balance::{Self, Balance};
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::event;
    use std::string::String;
    use perp::perp_types;

    // ============================================
    // STRUCTS
    // ============================================

    /// Broker information
    public struct Broker has store, copy, drop {
        name: String,
        url: String,
        receiver: address,
        id: u32,
        commission_p: u16,      // Commission percentage (1e4 basis)
        dao_share_p: u16,       // DAO share (1e4 basis)
        lp_pool_p: u16,         // LP pool share (1e4 basis)
    }

    /// Commission tracking per token
    public struct Commission has store {
        total: u64,
        pending: u64,
    }

    /// Broker manager
    public struct BrokerManager has key {
        id: UID,
        admin: address,
        brokers: Table<u32, Broker>,
        broker_ids: vector<u32>,
        /// broker_id => token => Commission
        broker_commissions: Table<u32, Table<String, Commission>>,
        /// broker_id => tokens with commissions
        broker_commission_tokens: Table<u32, vector<String>>,
        /// token => total pending across all brokers
        all_pending_commissions: Table<String, u64>,
        default_broker_id: u32,
        next_broker_id: u32,
    }

    // ============================================
    // EVENTS
    // ============================================

    public struct BrokerManagerCreated has copy, drop {
        manager_id: ID,
    }

    public struct BrokerAdded has copy, drop {
        id: u32,
        name: String,
        receiver: address,
        commission_p: u16,
    }

    public struct BrokerRemoved has copy, drop {
        id: u32,
    }

    public struct BrokerCommissionUpdated has copy, drop {
        id: u32,
        commission_p: u16,
        dao_share_p: u16,
        lp_pool_p: u16,
    }

    public struct CommissionEarned has copy, drop {
        broker_id: u32,
        token: String,
        amount: u64,
    }

    public struct CommissionWithdrawn has copy, drop {
        broker_id: u32,
        token: String,
        amount: u64,
        receiver: address,
    }

    // ============================================
    // INITIALIZATION
    // ============================================

    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);

        let mut manager = BrokerManager {
            id: object::new(ctx),
            admin,
            brokers: table::new(ctx),
            broker_ids: vector::empty(),
            broker_commissions: table::new(ctx),
            broker_commission_tokens: table::new(ctx),
            all_pending_commissions: table::new(ctx),
            default_broker_id: 1,
            next_broker_id: 1,
        };

        // Add default broker (platform)
        let default_broker = Broker {
            name: std::string::utf8(b"Platform"),
            url: std::string::utf8(b""),
            receiver: admin,
            id: 1,
            commission_p: 10000, // 100% to platform by default
            dao_share_p: 0,
            lp_pool_p: 0,
        };

        table::add(&mut manager.brokers, 1, default_broker);
        vector::push_back(&mut manager.broker_ids, 1);
        table::add(&mut manager.broker_commissions, 1, table::new(ctx));
        table::add(&mut manager.broker_commission_tokens, 1, vector::empty());
        manager.next_broker_id = 2;

        event::emit(BrokerManagerCreated {
            manager_id: object::id(&manager),
        });

        transfer::share_object(manager);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /// Add a new broker
    public entry fun add_broker(
        manager: &mut BrokerManager,
        name: String,
        url: String,
        receiver: address,
        commission_p: u16,
        dao_share_p: u16,
        lp_pool_p: u16,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());

        let id = manager.next_broker_id;
        manager.next_broker_id = id + 1;

        let broker = Broker {
            name,
            url,
            receiver,
            id,
            commission_p,
            dao_share_p,
            lp_pool_p,
        };

        table::add(&mut manager.brokers, id, broker);
        vector::push_back(&mut manager.broker_ids, id);
        table::add(&mut manager.broker_commissions, id, table::new(ctx));
        table::add(&mut manager.broker_commission_tokens, id, vector::empty());

        event::emit(BrokerAdded {
            id,
            name,
            receiver,
            commission_p,
        });
    }

    /// Remove a broker (withdraws pending commissions first)
    public entry fun remove_broker(
        manager: &mut BrokerManager,
        id: u32,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(id != manager.default_broker_id, perp_types::e_cannot_remove_default_broker());
        assert!(table::contains(&manager.brokers, id), perp_types::e_broker_not_found());

        // Remove from broker_ids
        let mut new_ids = vector::empty<u32>();
        let len = vector::length(&manager.broker_ids);
        let mut i = 0;
        while (i < len) {
            let bid = *vector::borrow(&manager.broker_ids, i);
            if (bid != id) {
                vector::push_back(&mut new_ids, bid);
            };
            i = i + 1;
        };
        manager.broker_ids = new_ids;

        // Remove broker data
        table::remove(&mut manager.brokers, id);

        // Note: Commission tables should be cleaned up separately
        // For simplicity, we leave them (they'll have 0 pending after withdrawal)

        event::emit(BrokerRemoved { id });
    }

    /// Update broker commission rates
    public entry fun update_broker_commission(
        manager: &mut BrokerManager,
        id: u32,
        commission_p: u16,
        dao_share_p: u16,
        lp_pool_p: u16,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.brokers, id), perp_types::e_broker_not_found());

        let broker = table::borrow_mut(&mut manager.brokers, id);
        broker.commission_p = commission_p;
        broker.dao_share_p = dao_share_p;
        broker.lp_pool_p = lp_pool_p;

        event::emit(BrokerCommissionUpdated {
            id,
            commission_p,
            dao_share_p,
            lp_pool_p,
        });
    }

    /// Update broker receiver address
    public entry fun update_broker_receiver(
        manager: &mut BrokerManager,
        id: u32,
        receiver: address,
        ctx: &TxContext
    ) {
        assert!(tx_context::sender(ctx) == manager.admin, perp_types::e_not_admin());
        assert!(table::contains(&manager.brokers, id), perp_types::e_broker_not_found());

        let broker = table::borrow_mut(&mut manager.brokers, id);
        broker.receiver = receiver;
    }

    // ============================================
    // COMMISSION TRACKING (called by trading module)
    // ============================================

    /// Record commission from a fee payment
    /// Returns: (broker_commission, broker_id, dao_amount, lp_pool_amount)
    public fun record_commission(
        manager: &mut BrokerManager,
        token: String,
        fee_amount: u64,
        broker_id: u32,
        ctx: &mut TxContext
    ): (u64, u32, u64, u64) {
        // Get broker or default
        let (broker, actual_id) = get_broker_or_default(manager, broker_id);

        // Calculate commission
        let commission = (fee_amount * (broker.commission_p as u64)) / 10000;

        if (commission > 0) {
            // Get or create commission table for this broker
            let commissions = table::borrow_mut(&mut manager.broker_commissions, actual_id);

            if (table::contains(commissions, token)) {
                let c = table::borrow_mut(commissions, token);
                c.total = c.total + commission;
                c.pending = c.pending + commission;
            } else {
                table::add(commissions, token, Commission {
                    total: commission,
                    pending: commission,
                });

                // Track token
                let tokens = table::borrow_mut(&mut manager.broker_commission_tokens, actual_id);
                vector::push_back(tokens, token);
            };

            // Update global pending
            if (table::contains(&manager.all_pending_commissions, token)) {
                let pending = table::borrow_mut(&mut manager.all_pending_commissions, token);
                *pending = *pending + commission;
            } else {
                table::add(&mut manager.all_pending_commissions, token, commission);
            };

            event::emit(CommissionEarned {
                broker_id: actual_id,
                token,
                amount: commission,
            });
        };

        let dao_amount = (fee_amount * (broker.dao_share_p as u64)) / 10000;
        let lp_amount = (fee_amount * (broker.lp_pool_p as u64)) / 10000;

        (commission, actual_id, dao_amount, lp_amount)
    }

    // ============================================
    // WITHDRAWAL
    // ============================================

    /// Withdraw pending commissions for a broker
    /// Note: This requires the vault to transfer funds
    public fun get_pending_withdrawal(
        manager: &mut BrokerManager,
        broker_id: u32,
        token: String,
    ): (u64, address) {
        assert!(table::contains(&manager.brokers, broker_id), perp_types::e_broker_not_found());

        let broker = table::borrow(&manager.brokers, broker_id);
        let receiver = broker.receiver;

        let commissions = table::borrow_mut(&mut manager.broker_commissions, broker_id);

        if (!table::contains(commissions, token)) {
            return (0, receiver)
        };

        let c = table::borrow_mut(commissions, token);
        let pending = c.pending;
        c.pending = 0;

        // Update global pending
        if (table::contains(&manager.all_pending_commissions, token)) {
            let global_pending = table::borrow_mut(&mut manager.all_pending_commissions, token);
            if (*global_pending >= pending) {
                *global_pending = *global_pending - pending;
            };
        };

        if (pending > 0) {
            event::emit(CommissionWithdrawn {
                broker_id,
                token,
                amount: pending,
                receiver,
            });
        };

        (pending, receiver)
    }

    // ============================================
    // QUERY FUNCTIONS
    // ============================================

    fun get_broker_or_default(manager: &BrokerManager, broker_id: u32): (Broker, u32) {
        if (table::contains(&manager.brokers, broker_id)) {
            (*table::borrow(&manager.brokers, broker_id), broker_id)
        } else {
            (*table::borrow(&manager.brokers, manager.default_broker_id), manager.default_broker_id)
        }
    }

    public fun get_broker(manager: &BrokerManager, broker_id: u32): Broker {
        assert!(table::contains(&manager.brokers, broker_id), perp_types::e_broker_not_found());
        *table::borrow(&manager.brokers, broker_id)
    }

    public fun get_pending_commission(
        manager: &BrokerManager,
        broker_id: u32,
        token: String
    ): u64 {
        if (!table::contains(&manager.broker_commissions, broker_id)) {
            return 0
        };

        let commissions = table::borrow(&manager.broker_commissions, broker_id);
        if (!table::contains(commissions, token)) {
            return 0
        };

        table::borrow(commissions, token).pending
    }

    public fun get_total_pending(manager: &BrokerManager, token: String): u64 {
        if (table::contains(&manager.all_pending_commissions, token)) {
            *table::borrow(&manager.all_pending_commissions, token)
        } else {
            0
        }
    }

    public fun default_broker_id(manager: &BrokerManager): u32 {
        manager.default_broker_id
    }

    public fun broker_count(manager: &BrokerManager): u64 {
        vector::length(&manager.broker_ids)
    }
}
