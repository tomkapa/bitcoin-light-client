#[test_only]
module zcash_spv::params_test {
    use zcash_spv::params;
    use sui::test_utils::destroy;

    #[test]
    fun test_params_struct_fields() {
        // Test that Params struct can be instantiated with all required fields
        let p = params::testnet();

        // Verify field getters exist and return expected types
        let _power_limit = params::power_limit(&p);
        let _power_limit_bits = params::power_limit_bits(&p);
        let _target_spacing = params::target_spacing(&p);
        let _averaging_window = params::averaging_window(&p);
        let _median_time_span = params::median_time_span(&p);
        let _equihash_n = params::equihash_n(&p);
        let _equihash_k = params::equihash_k(&p);

        // Verify DigiShield check function exists
        let _is_digishield = params::is_digishield(&p);

        destroy(p);
    }

    #[test]
    fun test_testnet_params_values() {
        let p = params::testnet();

        // Verify testnet-specific values
        assert!(params::target_spacing(&p) == 75, 0); // 75 seconds
        assert!(params::averaging_window(&p) == 17, 1); // 17 blocks
        assert!(params::median_time_span(&p) == 11, 2); // 11 blocks
        assert!(params::equihash_n(&p) == 144, 3); // n=144 for testnet
        assert!(params::equihash_k(&p) == 5, 4); // k=5 for testnet
        assert!(params::is_digishield(&p), 5); // Should use DigiShield
        assert!(params::power_limit_bits(&p) == 0x2007ffff, 6);

        destroy(p);
    }

    #[test]
    fun test_mainnet_params_values() {
        let p = params::mainnet();

        // Verify mainnet Equihash parameters
        assert!(params::equihash_n(&p) == 200, 0); // n=200 for mainnet
        assert!(params::equihash_k(&p) == 9, 1); // k=9 for mainnet
        assert!(params::target_spacing(&p) == 75, 2); // Same 75 seconds
        assert!(params::averaging_window(&p) == 17, 3); // Same DigiShield window
        assert!(params::is_digishield(&p), 4); // Should use DigiShield

        destroy(p);
    }

    #[test]
    fun test_power_limit_consistency() {
        let testnet = params::testnet();
        let mainnet = params::mainnet();

        // Verify power_limit is the same for both networks (Zcash uses same PoW limit)
        assert!(params::power_limit(&testnet) == params::power_limit(&mainnet), 0);
        assert!(params::power_limit_bits(&testnet) == params::power_limit_bits(&mainnet), 1);

        // Verify the actual power_limit value
        assert!(params::power_limit(&testnet) ==
            0x0007ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff, 2);

        destroy(testnet);
        destroy(mainnet);
    }

    #[test]
    fun test_mainnet_testnet_common_params() {
        let testnet = params::testnet();
        let mainnet = params::mainnet();

        // These consensus parameters should be identical for both networks
        assert!(params::target_spacing(&testnet) == params::target_spacing(&mainnet), 0);
        assert!(params::averaging_window(&testnet) == params::averaging_window(&mainnet), 1);
        assert!(params::median_time_span(&testnet) == params::median_time_span(&mainnet), 2);
        assert!(params::is_digishield(&testnet) == params::is_digishield(&mainnet), 3);

        destroy(testnet);
        destroy(mainnet);
    }

    #[test]
    fun test_equihash_params_differ() {
        let testnet = params::testnet();
        let mainnet = params::mainnet();

        // Equihash parameters should differ between networks
        assert!(params::equihash_n(&testnet) == 144, 0); // testnet uses 144
        assert!(params::equihash_n(&mainnet) == 200, 1); // mainnet uses 200
        assert!(params::equihash_k(&testnet) == 5, 2);   // testnet uses 5
        assert!(params::equihash_k(&mainnet) == 9, 3);   // mainnet uses 9

        destroy(testnet);
        destroy(mainnet);
    }
}
