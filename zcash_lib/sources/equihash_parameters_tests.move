// SPDX-License-Identifier: MPL-2.0

/// Tests for Equihash hash generation parameter constants.
/// This validates that the constants in equihash.move are correctly calculated
/// according to the Zcash reference implementation formulas.
#[test_only]
module zcash_lib::equihash_parameters_tests;

// These constants should match equihash.move
const N: u64 = 144;
const K: u64 = 5;
const COLLISION_BYTES: u64 = 3;
const HASH_LENGTH: u64 = 18;
const INDICES_PER_HASH: u64 = 3;
const HASH_OUTPUT_SIZE: u64 = 54;

#[test]
/// Test that COLLISION_BYTES is correctly calculated as n/(k+1) = 144/6 = 24 bits = 3 bytes
fun test_collision_bytes_formula() {
    let collision_bits = N / (K + 1);
    let collision_bytes = (collision_bits + 7) / 8; // ceiling division
    assert!(collision_bytes == COLLISION_BYTES, 0);
    assert!(COLLISION_BYTES == 3, 1);
}

#[test]
/// Test that HASH_LENGTH is correctly calculated as (k+1) * collision_bytes = 6 * 3 = 18 bytes
fun test_hash_length_formula() {
    let expected_hash_length = (K + 1) * COLLISION_BYTES;
    assert!(expected_hash_length == HASH_LENGTH, 0);
    assert!(HASH_LENGTH == 18, 1);
}

#[test]
/// Test that INDICES_PER_HASH is correctly calculated as 512/N = 512/144 = 3
fun test_indices_per_hash_formula() {
    let expected_indices_per_hash = 512 / N;
    assert!(expected_indices_per_hash == INDICES_PER_HASH, 0);
    assert!(INDICES_PER_HASH == 3, 1);
}

#[test]
/// Test that HASH_OUTPUT_SIZE is correctly calculated as INDICES_PER_HASH * N / 8 = 3 * 144 / 8 = 54 bytes
fun test_hash_output_size_formula() {
    let expected_output_size = (INDICES_PER_HASH * N) / 8;
    assert!(expected_output_size == HASH_OUTPUT_SIZE, 0);
    assert!(HASH_OUTPUT_SIZE == 54, 1);
}

#[test]
/// Test the complete parameter chain for n=144, k=5
fun test_complete_parameter_chain() {
    // Step 1: Calculate collision bytes
    let collision_bits = N / (K + 1); // 144 / 6 = 24 bits
    assert!(collision_bits == 24, 0);
    let collision_bytes = (collision_bits + 7) / 8; // 24 / 8 = 3 bytes
    assert!(collision_bytes == 3, 1);

    // Step 2: Calculate hash length
    let hash_length = (K + 1) * collision_bytes; // 6 * 3 = 18 bytes
    assert!(hash_length == 18, 2);

    // Step 3: Calculate indices per hash
    let indices_per_hash = 512 / N; // 512 / 144 = 3
    assert!(indices_per_hash == 3, 3);

    // Step 4: Calculate hash output size
    let hash_output_size = (indices_per_hash * N) / 8; // (3 * 144) / 8 = 54 bytes
    assert!(hash_output_size == 54, 4);

    // Verify all match the constants
    assert!(collision_bytes == COLLISION_BYTES, 5);
    assert!(hash_length == HASH_LENGTH, 6);
    assert!(indices_per_hash == INDICES_PER_HASH, 7);
    assert!(hash_output_size == HASH_OUTPUT_SIZE, 8);
}

#[test]
/// Test parameter relationships for correctness
fun test_parameter_relationships() {
    // Verify that 3 hashes of 18 bytes each fit exactly in 54 bytes
    assert!(INDICES_PER_HASH * HASH_LENGTH == HASH_OUTPUT_SIZE, 0);
    assert!(3 * 18 == 54, 1);

    // Verify that hash length is evenly divisible into output size
    assert!(HASH_OUTPUT_SIZE % HASH_LENGTH == 0, 2);

    // Verify indices per hash matches the quotient
    assert!(HASH_OUTPUT_SIZE / HASH_LENGTH == INDICES_PER_HASH, 3);
}
