/// Core types, constants, and errors for the perpetual exchange
module perp::perp_types {
    use std::string::String;

    // ============================================
    // PRECISION CONSTANTS
    // ============================================

    /// Basis points divisor (1e4)
    const BPS: u64 = 10000;
    /// Higher precision divisor (1e5)
    const PRECISION_5: u64 = 100000;
    /// Price precision (1e10 for USD prices)
    const PRICE_PRECISION: u64 = 10000000000;
    /// Funding rate precision (1e18)
    const FUNDING_PRECISION: u128 = 1000000000000000000;
    /// Holding fee precision (1e12)
    const HOLDING_FEE_PRECISION: u64 = 1000000000000;

    // ============================================
    // ERROR CODES
    // ============================================

    // Config errors (1xx)
    const E_NOT_ADMIN: u64 = 100;
    const E_PAIR_EXISTS: u64 = 101;
    const E_PAIR_NOT_FOUND: u64 = 102;
    const E_FEE_CONFIG_NOT_FOUND: u64 = 103;
    const E_SLIPPAGE_CONFIG_NOT_FOUND: u64 = 104;
    const E_INVALID_LEVERAGE_TIER: u64 = 105;
    const E_TRADING_DISABLED: u64 = 106;
    const E_PAIR_CLOSED: u64 = 107;

    // Trading errors (2xx)
    const E_INSUFFICIENT_MARGIN: u64 = 200;
    const E_LEVERAGE_TOO_HIGH: u64 = 201;
    const E_POSITION_TOO_SMALL: u64 = 202;
    const E_POSITION_TOO_LARGE: u64 = 203;
    const E_OI_LIMIT_EXCEEDED: u64 = 204;
    const E_INVALID_STOP_LOSS: u64 = 205;
    const E_INVALID_TAKE_PROFIT: u64 = 206;
    const E_NOT_POSITION_OWNER: u64 = 207;
    const E_POSITION_NOT_LIQUIDATABLE: u64 = 208;
    const E_PENDING_TRADE_NOT_FOUND: u64 = 209;
    const E_TRADE_EXPIRED: u64 = 210;

    // Vault errors (3xx)
    const E_INSUFFICIENT_LIQUIDITY: u64 = 300;
    const E_INSUFFICIENT_BALANCE: u64 = 301;
    const E_TOKEN_NOT_SUPPORTED: u64 = 302;
    const E_WITHDRAWAL_LOCKED: u64 = 303;

    // Oracle errors (4xx)
    const E_PRICE_STALE: u64 = 400;
    const E_INVALID_PRICE: u64 = 401;
    const E_PRICE_DEVIATION_TOO_HIGH: u64 = 402;

    // Broker errors (5xx)
    const E_BROKER_EXISTS: u64 = 500;
    const E_BROKER_NOT_FOUND: u64 = 501;
    const E_CANNOT_REMOVE_DEFAULT_BROKER: u64 = 502;

    // Order errors (6xx)
    const E_ORDER_NOT_FOUND: u64 = 600;
    const E_ORDER_NOT_FILLABLE: u64 = 601;
    const E_ORDER_EXPIRED: u64 = 602;
    const E_INVALID_ORDER_TYPE: u64 = 603;
    const E_ORDER_ALREADY_FILLED: u64 = 604;
    const E_INVALID_LIMIT_PRICE: u64 = 605;

    // ADL errors (7xx)
    const E_ADL_NOT_TRIGGERED: u64 = 700;
    const E_NO_POSITIONS_TO_ADL: u64 = 701;
    const E_ADL_DISABLED: u64 = 702;

    // Insurance errors (8xx)
    const E_INSURANCE_INSUFFICIENT: u64 = 800;
    const E_INSURANCE_PAUSED: u64 = 801;

    // Margin mode errors (9xx)
    const E_INVALID_MARGIN_MODE: u64 = 900;
    const E_CROSS_MARGIN_LIQUIDATION: u64 = 901;
    const E_CANNOT_CHANGE_MARGIN_MODE: u64 = 902;

    // ============================================
    // PAIR STATUS
    // ============================================

    const PAIR_ACTIVE: u8 = 0;
    const PAIR_CLOSE_ONLY: u8 = 1;
    const PAIR_CLOSED: u8 = 2;

    // ============================================
    // PAIR TYPES
    // ============================================

    const PAIR_CRYPTO: u8 = 0;
    const PAIR_FOREX: u8 = 1;
    const PAIR_COMMODITIES: u8 = 2;
    const PAIR_INDICES: u8 = 3;

    // ============================================
    // ORDER TYPES
    // ============================================

    const ORDER_MARKET: u8 = 0;
    const ORDER_LIMIT: u8 = 1;
    const ORDER_STOP_MARKET: u8 = 2;
    const ORDER_STOP_LIMIT: u8 = 3;
    const ORDER_TAKE_PROFIT_MARKET: u8 = 4;
    const ORDER_TAKE_PROFIT_LIMIT: u8 = 5;

    // ============================================
    // ORDER STATUS
    // ============================================

    const ORDER_STATUS_OPEN: u8 = 0;
    const ORDER_STATUS_FILLED: u8 = 1;
    const ORDER_STATUS_CANCELLED: u8 = 2;
    const ORDER_STATUS_EXPIRED: u8 = 3;
    const ORDER_STATUS_PARTIALLY_FILLED: u8 = 4;

    // ============================================
    // MARGIN MODES
    // ============================================

    const MARGIN_ISOLATED: u8 = 0;
    const MARGIN_CROSS: u8 = 1;

    // ============================================
    // STRUCTS
    // ============================================

    /// Leverage margin tier configuration
    public struct LeverageMargin has store, copy, drop {
        notional_usd: u64,      // Max notional for this tier
        tier: u16,              // Tier number
        max_leverage: u16,      // Max leverage allowed
        initial_lost_p: u16,    // Initial margin call threshold (bps)
        liq_lost_p: u16,        // Liquidation threshold (bps)
    }

    /// Fee configuration for a pair/group
    public struct FeeConfig has store, copy, drop {
        name: String,
        index: u16,
        open_fee_p: u16,        // Opening fee (bps)
        close_fee_p: u16,       // Closing fee (bps)
        share_p: u32,           // PnL share for close fee (1e5)
        min_close_fee_p: u32,   // Minimum close fee (1e5)
        enable: bool,
    }

    /// Slippage configuration
    public struct SlippageConfig has store, copy, drop {
        name: String,
        index: u16,
        one_pct_depth_above_usd: u64,   // 1% depth for longs
        one_pct_depth_below_usd: u64,   // 1% depth for shorts
        slippage_long_p: u16,           // Base slippage longs (bps)
        slippage_short_p: u16,          // Base slippage shorts (bps)
        long_threshold_usd: u64,        // Threshold for dynamic slippage
        short_threshold_usd: u64,
        enable: bool,
    }

    /// Signed value (Move doesn't have signed integers)
    public struct SignedValue has store, copy, drop {
        value: u64,
        is_negative: bool,
    }

    // ============================================
    // SIGNED VALUE HELPERS
    // ============================================

    public fun new_signed(value: u64, is_negative: bool): SignedValue {
        SignedValue { value, is_negative }
    }

    public fun zero_signed(): SignedValue {
        SignedValue { value: 0, is_negative: false }
    }

    public fun signed_value(s: &SignedValue): u64 { s.value }
    public fun signed_is_negative(s: &SignedValue): bool { s.is_negative }

    public fun add_signed(a: SignedValue, b: SignedValue): SignedValue {
        if (a.is_negative == b.is_negative) {
            SignedValue { value: a.value + b.value, is_negative: a.is_negative }
        } else if (a.value >= b.value) {
            SignedValue { value: a.value - b.value, is_negative: a.is_negative }
        } else {
            SignedValue { value: b.value - a.value, is_negative: b.is_negative }
        }
    }

    // ============================================
    // LEVERAGE MARGIN HELPERS
    // ============================================

    public fun new_leverage_margin(
        notional_usd: u64,
        tier: u16,
        max_leverage: u16,
        initial_lost_p: u16,
        liq_lost_p: u16,
    ): LeverageMargin {
        LeverageMargin { notional_usd, tier, max_leverage, initial_lost_p, liq_lost_p }
    }

    public fun lm_notional(lm: &LeverageMargin): u64 { lm.notional_usd }
    public fun lm_tier(lm: &LeverageMargin): u16 { lm.tier }
    public fun lm_max_leverage(lm: &LeverageMargin): u16 { lm.max_leverage }
    public fun lm_initial_lost_p(lm: &LeverageMargin): u16 { lm.initial_lost_p }
    public fun lm_liq_lost_p(lm: &LeverageMargin): u16 { lm.liq_lost_p }

    // ============================================
    // FEE CONFIG HELPERS
    // ============================================

    public fun new_fee_config(
        name: String,
        index: u16,
        open_fee_p: u16,
        close_fee_p: u16,
        share_p: u32,
        min_close_fee_p: u32,
    ): FeeConfig {
        FeeConfig { name, index, open_fee_p, close_fee_p, share_p, min_close_fee_p, enable: true }
    }

    public fun fc_open_fee_p(fc: &FeeConfig): u16 { fc.open_fee_p }
    public fun fc_close_fee_p(fc: &FeeConfig): u16 { fc.close_fee_p }
    public fun fc_share_p(fc: &FeeConfig): u32 { fc.share_p }
    public fun fc_min_close_fee_p(fc: &FeeConfig): u32 { fc.min_close_fee_p }
    public fun fc_enabled(fc: &FeeConfig): bool { fc.enable }

    // ============================================
    // SLIPPAGE CONFIG HELPERS
    // ============================================

    public fun new_slippage_config(
        name: String,
        index: u16,
        one_pct_depth_above_usd: u64,
        one_pct_depth_below_usd: u64,
        slippage_long_p: u16,
        slippage_short_p: u16,
        long_threshold_usd: u64,
        short_threshold_usd: u64,
    ): SlippageConfig {
        SlippageConfig {
            name, index,
            one_pct_depth_above_usd, one_pct_depth_below_usd,
            slippage_long_p, slippage_short_p,
            long_threshold_usd, short_threshold_usd,
            enable: true,
        }
    }

    public fun sc_one_pct_depth_above(sc: &SlippageConfig): u64 { sc.one_pct_depth_above_usd }
    public fun sc_one_pct_depth_below(sc: &SlippageConfig): u64 { sc.one_pct_depth_below_usd }
    public fun sc_slippage_long_p(sc: &SlippageConfig): u16 { sc.slippage_long_p }
    public fun sc_slippage_short_p(sc: &SlippageConfig): u16 { sc.slippage_short_p }
    public fun sc_long_threshold(sc: &SlippageConfig): u64 { sc.long_threshold_usd }
    public fun sc_short_threshold(sc: &SlippageConfig): u64 { sc.short_threshold_usd }
    public fun sc_enabled(sc: &SlippageConfig): bool { sc.enable }

    // ============================================
    // CONSTANT GETTERS
    // ============================================

    public fun bps(): u64 { BPS }
    public fun precision_5(): u64 { PRECISION_5 }
    public fun price_precision(): u64 { PRICE_PRECISION }
    public fun funding_precision(): u128 { FUNDING_PRECISION }
    public fun holding_fee_precision(): u64 { HOLDING_FEE_PRECISION }

    // Status constants
    public fun pair_active(): u8 { PAIR_ACTIVE }
    public fun pair_close_only(): u8 { PAIR_CLOSE_ONLY }
    public fun pair_closed(): u8 { PAIR_CLOSED }

    // Type constants
    public fun pair_crypto(): u8 { PAIR_CRYPTO }
    public fun pair_forex(): u8 { PAIR_FOREX }
    public fun pair_commodities(): u8 { PAIR_COMMODITIES }
    public fun pair_indices(): u8 { PAIR_INDICES }

    // Error getters
    public fun e_not_admin(): u64 { E_NOT_ADMIN }
    public fun e_pair_exists(): u64 { E_PAIR_EXISTS }
    public fun e_pair_not_found(): u64 { E_PAIR_NOT_FOUND }
    public fun e_fee_config_not_found(): u64 { E_FEE_CONFIG_NOT_FOUND }
    public fun e_slippage_config_not_found(): u64 { E_SLIPPAGE_CONFIG_NOT_FOUND }
    public fun e_invalid_leverage_tier(): u64 { E_INVALID_LEVERAGE_TIER }
    public fun e_trading_disabled(): u64 { E_TRADING_DISABLED }
    public fun e_pair_closed(): u64 { E_PAIR_CLOSED }
    public fun e_insufficient_margin(): u64 { E_INSUFFICIENT_MARGIN }
    public fun e_leverage_too_high(): u64 { E_LEVERAGE_TOO_HIGH }
    public fun e_position_too_small(): u64 { E_POSITION_TOO_SMALL }
    public fun e_position_too_large(): u64 { E_POSITION_TOO_LARGE }
    public fun e_oi_limit_exceeded(): u64 { E_OI_LIMIT_EXCEEDED }
    public fun e_invalid_stop_loss(): u64 { E_INVALID_STOP_LOSS }
    public fun e_invalid_take_profit(): u64 { E_INVALID_TAKE_PROFIT }
    public fun e_not_position_owner(): u64 { E_NOT_POSITION_OWNER }
    public fun e_position_not_liquidatable(): u64 { E_POSITION_NOT_LIQUIDATABLE }
    public fun e_pending_trade_not_found(): u64 { E_PENDING_TRADE_NOT_FOUND }
    public fun e_trade_expired(): u64 { E_TRADE_EXPIRED }
    public fun e_insufficient_liquidity(): u64 { E_INSUFFICIENT_LIQUIDITY }
    public fun e_insufficient_balance(): u64 { E_INSUFFICIENT_BALANCE }
    public fun e_token_not_supported(): u64 { E_TOKEN_NOT_SUPPORTED }
    public fun e_withdrawal_locked(): u64 { E_WITHDRAWAL_LOCKED }
    public fun e_price_stale(): u64 { E_PRICE_STALE }
    public fun e_invalid_price(): u64 { E_INVALID_PRICE }
    public fun e_price_deviation_too_high(): u64 { E_PRICE_DEVIATION_TOO_HIGH }
    public fun e_broker_exists(): u64 { E_BROKER_EXISTS }
    public fun e_broker_not_found(): u64 { E_BROKER_NOT_FOUND }
    public fun e_cannot_remove_default_broker(): u64 { E_CANNOT_REMOVE_DEFAULT_BROKER }

    // Order errors
    public fun e_order_not_found(): u64 { E_ORDER_NOT_FOUND }
    public fun e_order_not_fillable(): u64 { E_ORDER_NOT_FILLABLE }
    public fun e_order_expired(): u64 { E_ORDER_EXPIRED }
    public fun e_invalid_order_type(): u64 { E_INVALID_ORDER_TYPE }
    public fun e_order_already_filled(): u64 { E_ORDER_ALREADY_FILLED }
    public fun e_invalid_limit_price(): u64 { E_INVALID_LIMIT_PRICE }

    // ADL errors
    public fun e_adl_not_triggered(): u64 { E_ADL_NOT_TRIGGERED }
    public fun e_no_positions_to_adl(): u64 { E_NO_POSITIONS_TO_ADL }
    public fun e_adl_disabled(): u64 { E_ADL_DISABLED }

    // Insurance errors
    public fun e_insurance_insufficient(): u64 { E_INSURANCE_INSUFFICIENT }
    public fun e_insurance_paused(): u64 { E_INSURANCE_PAUSED }

    // Margin mode errors
    public fun e_invalid_margin_mode(): u64 { E_INVALID_MARGIN_MODE }
    public fun e_cross_margin_liquidation(): u64 { E_CROSS_MARGIN_LIQUIDATION }
    public fun e_cannot_change_margin_mode(): u64 { E_CANNOT_CHANGE_MARGIN_MODE }

    // Order type getters
    public fun order_market(): u8 { ORDER_MARKET }
    public fun order_limit(): u8 { ORDER_LIMIT }
    public fun order_stop_market(): u8 { ORDER_STOP_MARKET }
    public fun order_stop_limit(): u8 { ORDER_STOP_LIMIT }
    public fun order_take_profit_market(): u8 { ORDER_TAKE_PROFIT_MARKET }
    public fun order_take_profit_limit(): u8 { ORDER_TAKE_PROFIT_LIMIT }

    // Order status getters
    public fun order_status_open(): u8 { ORDER_STATUS_OPEN }
    public fun order_status_filled(): u8 { ORDER_STATUS_FILLED }
    public fun order_status_cancelled(): u8 { ORDER_STATUS_CANCELLED }
    public fun order_status_expired(): u8 { ORDER_STATUS_EXPIRED }
    public fun order_status_partially_filled(): u8 { ORDER_STATUS_PARTIALLY_FILLED }

    // Margin mode getters
    public fun margin_isolated(): u8 { MARGIN_ISOLATED }
    public fun margin_cross(): u8 { MARGIN_CROSS }
}
