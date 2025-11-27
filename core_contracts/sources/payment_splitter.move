module core_contracts::payment_splitter {
    use one::coin::{Self, Coin};
    use one::oct::OCT;
    use one::event;
    use one::transfer;
    use one::tx_context;
    use std::vector;

    // Event emitted when payment is split
    public struct PaymentSplit has copy, drop {
        payer: address,
        recipients: vector<address>,
        amounts: vector<u64>,
        timestamp: u64,
    }

    /// Split payment among multiple recipients
    public entry fun split_payment(
        mut payment: Coin<OCT>,
        recipients: vector<address>,
        amounts: vector<u64>,
        ctx: &mut TxContext
    ) {
        // Validate inputs
        assert!(vector::length(&recipients) == vector::length(&amounts), 0);

        let mut total: u64 = 0;
        let mut i = 0;

        while (i < vector::length(&amounts)) {
            total = total + *vector::borrow(&amounts, i);
            i = i + 1;
        };

        assert!(coin::value(&payment) >= total, 1);

        // Split and transfer
        let mut i = 0;
        while (i < vector::length(&recipients)) {
            let amount = *vector::borrow(&amounts, i);
            let recipient = *vector::borrow(&recipients, i);

            // ✅ THIS IS THE CRUCIAL FIX
            let split_coin = coin::split(&mut payment, amount, ctx);

            transfer::public_transfer(split_coin, recipient);
            i = i + 1;
        };

        // Return change to sender
        transfer::public_transfer(payment, tx_context::sender(ctx));

        // Emit event
        event::emit(PaymentSplit {
            payer: tx_context::sender(ctx),
            recipients,
            amounts,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    }
}


