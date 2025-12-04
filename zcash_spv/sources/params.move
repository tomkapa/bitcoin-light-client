// SPDX-License-Identifier: MPL-2.0

module zcash_spv::params;

/// Zcash network parameters
public struct Params has store, drop {
    power_limit: u256,
    power_limit_bits: u32,
    target_spacing: u64,      // Block time in seconds (75 for Zcash)
    averaging_window: u64,    // DigiShield averaging window (17 blocks)
    median_time_span: u64,    // Median time past window (11 blocks)
    equihash_n: u32,          // Equihash N parameter
    equihash_k: u32,          // Equihash K parameter
    difficulty_adjustment: u8, // Difficulty adjustment algorithm
}

const DIFFICULTYADJUSTMENT_DIGISHIELD: u8 = 3;

/// Default parameters for Zcash testnet
public fun testnet(): Params {
    Params {
        power_limit: 0x0007ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        power_limit_bits: 0x2007ffff,
        target_spacing: 75,
        averaging_window: 17,
        median_time_span: 11,
        equihash_n: 144,
        equihash_k: 5,
        difficulty_adjustment: DIFFICULTYADJUSTMENT_DIGISHIELD,
    }
}

/// Default parameters for Zcash mainnet
public fun mainnet(): Params {
    Params {
        power_limit: 0x0007ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        power_limit_bits: 0x2007ffff,
        target_spacing: 75,
        averaging_window: 17,
        median_time_span: 11,
        equihash_n: 200,
        equihash_k: 9,
        difficulty_adjustment: DIFFICULTYADJUSTMENT_DIGISHIELD,
    }
}

/// Get power limit (maximum target)
public fun power_limit(p: &Params): u256 {
    p.power_limit
}

/// Get power limit bits (compact representation)
public fun power_limit_bits(p: &Params): u32 {
    p.power_limit_bits
}

/// Get target block spacing in seconds
public fun target_spacing(p: &Params): u64 {
    p.target_spacing
}

/// Get DigiShield averaging window in blocks
public fun averaging_window(p: &Params): u64 {
    p.averaging_window
}

/// Get median time span in blocks
public fun median_time_span(p: &Params): u64 {
    p.median_time_span
}

/// Get Equihash N parameter
public fun equihash_n(p: &Params): u32 {
    p.equihash_n
}

/// Get Equihash K parameter
public fun equihash_k(p: &Params): u32 {
    p.equihash_k
}

/// Check if using DigiShield difficulty adjustment
public fun is_digishield(p: &Params): bool {
    p.difficulty_adjustment == DIFFICULTYADJUSTMENT_DIGISHIELD
}
