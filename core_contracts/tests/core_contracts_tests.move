#[test_only]
module core_contracts::core_contracts_tests {
    use one::test_scenario;
    use one::coin;            // ✅ import module
    use one::coin::Coin;      // ✅ import type
    use one::oct::OCT;
    use core_contracts::payment_splitter;

    #[test]
    fun test_split_payment() {
        let admin = @0xAD;
        let alice = @0xA11CE;
        let bob = @0xB0B;

        let mut scenario = test_scenario::begin(admin);
        {
            // Create test coin with 1000 OCT
            let payment = coin::mint_for_testing<OCT>(1000, scenario.ctx());

            let recipients = vector[alice, bob];
            let amounts = vector[300u64, 200u64];

            payment_splitter::split_payment(payment, recipients, amounts, scenario.ctx());
        };

        scenario.next_tx(alice);
        {
            let received: Coin<OCT> = scenario.take_from_sender<Coin<OCT>>();
            assert!(coin::value(&received) == 300, 0);
            scenario.return_to_sender(received);
        };

        scenario.next_tx(bob);
        {
            let received: Coin<OCT> = scenario.take_from_sender<Coin<OCT>>();
            assert!(coin::value(&received) == 200, 1);
            scenario.return_to_sender(received);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun test_split_payment_length_mismatch() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);
        {
            let payment = coin::mint_for_testing<OCT>(1000, scenario.ctx());

            let recipients = vector[@0xA11CE];
            let amounts = vector[300u64, 200u64]; // mismatch

            payment_splitter::split_payment(payment, recipients, amounts, scenario.ctx());
        };
        scenario.end();
    }
}
