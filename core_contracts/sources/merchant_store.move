module core_contracts::merchant_store {
    use one::object;
    use one::object::UID;
    use one::tx_context::TxContext;
    use one::transfer;
    use std::string::String;
    use std::vector;

    use core_contracts::product_catalog;

    /// Initialize merchant store
    public entry fun create_store(
        name: String,
        ctx: &mut TxContext
    ) {
        product_catalog::create_merchant_store(name, ctx);
    }
}