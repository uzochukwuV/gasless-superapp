module core_contracts::receipt_nft {
    use one::object;
    use one::object::{UID, ID};
    use one::tx_context::TxContext;
    use one::transfer;
    use one::url;
    use one::url::Url;
    use std::string::String;

    /// Receipt NFT given to customer after purchase
    public struct ReceiptNFT has key, store {
        id: UID,
        product_name: String,
        merchant: address,
        buyer: address,
        quantity: u64,
        amount_paid: u64,
        timestamp: u64,
        image_url: Url,
    }

    /// Mint receipt (callable from product_catalog only)
    public(package) fun mint(
        product_name: String,
        merchant: address,
        buyer: address,
        quantity: u64,
        amount_paid: u64,
        timestamp: u64,
        ctx: &mut TxContext
    ): ReceiptNFT {
        ReceiptNFT {
            id: object::new(ctx),
            product_name,
            merchant,
            buyer,
            quantity,
            amount_paid,
            timestamp,
            image_url: url::new_unsafe_from_bytes(b"https://example.com/receipt.png"),
        }
    }

    /// 🔹 NEW: Transfer receipt NFT to another address
    /// Alice can call this and send it to Bob.
    public entry fun transfer_receipt(
        receipt: ReceiptNFT,
        recipient: address,
        ctx: &mut TxContext
    ) {
        transfer::public_transfer(receipt, recipient);
    }

    /// Optional: Transfer and update buyer field
    /// If you want the new owner to become the new "buyer"
    public entry fun transfer_and_update_owner(
        mut receipt: ReceiptNFT,
        new_owner: address,
        ctx: &mut TxContext
    ) {
        receipt.buyer = new_owner;
        transfer::public_transfer(receipt, new_owner);
    }

    /// Read-only helper
    public fun get_receipt_details(receipt: &ReceiptNFT): (String, address, u64, u64) {
        (receipt.product_name, receipt.merchant, receipt.quantity, receipt.amount_paid)
    }

    /// Extra helper if UI needs current owner
    public fun get_buyer(receipt: &ReceiptNFT): address {
        receipt.buyer
    }
}
