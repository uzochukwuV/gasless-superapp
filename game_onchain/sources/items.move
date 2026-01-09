module game_onchain::items {
    use one::object::{Self, UID, ID};
    use one::tx_context::{Self, TxContext};
    use one::transfer;
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::balance::{Self, Balance};
    use one::event;
    use one::clock::{Self, Clock};

    // === Constants ===

    // Base price for immunity token (0.1 OCT = 100_000_000 MIST)
    const BASE_IMMUNITY_PRICE: u64 = 100_000_000;

    // === Error Codes ===
    const EInsufficientPayment: u64 = 200;
    const EInvalidTier: u64 = 201;

    // === Structs ===

    /// Global item shop
    public struct ItemShop has key {
        id: UID,
        revenue: Balance<OCT>,
        base_immunity_price: u64,
        total_immunity_sold: u64,
    }

    /// Immunity Token - protects from one round elimination
    public struct ImmunityToken has key, store {
        id: UID,
        owner: address,
        purchased_at: u64,
        tier: u8,  // Tier it was purchased for
    }

    // === Events ===

    public struct ItemShopCreated has copy, drop {
        shop_id: ID,
        base_immunity_price: u64,
    }

    public struct ImmunityTokenPurchased has copy, drop {
        token_id: ID,
        buyer: address,
        tier: u8,
        price_paid: u64,
        timestamp: u64,
    }

    public struct ImmunityTokenUsed has copy, drop {
        token_id: ID,
        game_id: ID,
        player: address,
        round: u64,
    }

    // === Initialization ===

    fun init(ctx: &mut TxContext) {
        let shop = ItemShop {
            id: object::new(ctx),
            revenue: balance::zero(),
            base_immunity_price: BASE_IMMUNITY_PRICE,
            total_immunity_sold: 0,
        };

        event::emit(ItemShopCreated {
            shop_id: object::id(&shop),
            base_immunity_price: BASE_IMMUNITY_PRICE,
        });

        transfer::share_object(shop);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    // === Public Functions ===

    /// Purchase immunity token with dynamic pricing based on tier
    public entry fun buy_immunity_token(
        shop: &mut ItemShop,
        tier: u8,
        mut payment: Coin<OCT>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate tier (1-5)
        assert!(tier >= 1 && tier <= 5, EInvalidTier);

        // Calculate price: base_price * tier
        let price = shop.base_immunity_price * (tier as u64);

        // Validate payment
        assert!(coin::value(&payment) >= price, EInsufficientPayment);

        let buyer = tx_context::sender(ctx);

        // Take payment
        let payment_coin = coin::split(&mut payment, price, ctx);
        balance::join(&mut shop.revenue, coin::into_balance(payment_coin));

        // Update stats
        shop.total_immunity_sold = shop.total_immunity_sold + 1;

        // Mint immunity token
        let token = ImmunityToken {
            id: object::new(ctx),
            owner: buyer,
            purchased_at: clock::timestamp_ms(clock),
            tier,
        };

        let token_id = object::id(&token);

        event::emit(ImmunityTokenPurchased {
            token_id,
            buyer,
            tier,
            price_paid: price,
            timestamp: clock::timestamp_ms(clock),
        });

        // Transfer token to buyer
        transfer::public_transfer(token, buyer);

        // Return change
        transfer::public_transfer(payment, buyer);
    }

    /// Burn immunity token (called by game contract)
    public fun burn_immunity_token(
        token: ImmunityToken,
        game_id: ID,
        round: u64,
    ) {
        let ImmunityToken { id, owner, purchased_at: _, tier: _ } = token;

        event::emit(ImmunityTokenUsed {
            token_id: object::uid_to_inner(&id),
            game_id,
            player: owner,
            round,
        });

        object::delete(id);
    }

    // === Admin Functions ===

    /// Withdraw shop revenue (TODO: add access control)
    public entry fun withdraw_shop_revenue(
        shop: &mut ItemShop,
        ctx: &mut TxContext
    ) {
        let amount = balance::value(&shop.revenue);

        if (amount > 0) {
            let coin = coin::from_balance(
                balance::withdraw_all(&mut shop.revenue),
                ctx
            );

            transfer::public_transfer(coin, tx_context::sender(ctx));
        }
    }

    /// Update base immunity price (TODO: add access control)
    public entry fun update_immunity_price(
        shop: &mut ItemShop,
        new_price: u64,
        _ctx: &mut TxContext
    ) {
        shop.base_immunity_price = new_price;
    }

    // === View Functions ===

    public fun get_shop_info(shop: &ItemShop): (u64, u64, u64) {
        (
            shop.base_immunity_price,
            balance::value(&shop.revenue),
            shop.total_immunity_sold
        )
    }

    public fun get_immunity_token_info(token: &ImmunityToken): (address, u64, u8) {
        (token.owner, token.purchased_at, token.tier)
    }

    public fun calculate_immunity_price(shop: &ItemShop, tier: u8): u64 {
        shop.base_immunity_price * (tier as u64)
    }

    public fun get_token_owner(token: &ImmunityToken): address {
        token.owner
    }
}
