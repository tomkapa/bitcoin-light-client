#[test_only]
module zcash_spv::params_test {
    use zcash_spv::params;

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
    }
}
