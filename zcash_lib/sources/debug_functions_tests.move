// SPDX-License-Identifier: MPL-2.0

/// Tests for Equihash debug functions.
#[test_only]
module zcash_lib::debug_functions_tests;

use zcash_lib::equihash;

#[test]
/// Test debug_block_index function
fun test_debug_block_index() {
    // Indices 0, 1, 2 -> block 0
    assert!(equihash::debug_block_index(0) == 0, 0);
    assert!(equihash::debug_block_index(1) == 0, 1);
    assert!(equihash::debug_block_index(2) == 0, 2);

    // Indices 3, 4, 5 -> block 1
    assert!(equihash::debug_block_index(3) == 1, 3);
    assert!(equihash::debug_block_index(4) == 1, 4);
    assert!(equihash::debug_block_index(5) == 1, 5);

    // Indices 6, 7, 8 -> block 2
    assert!(equihash::debug_block_index(6) == 2, 6);
    assert!(equihash::debug_block_index(7) == 2, 7);
    assert!(equihash::debug_block_index(8) == 2, 8);
}

#[test]
/// Test debug_hash_offset function
fun test_debug_hash_offset() {
    // Indices 0, 3, 6, ... -> offset 0
    assert!(equihash::debug_hash_offset(0) == 0, 0);
    assert!(equihash::debug_hash_offset(3) == 0, 1);
    assert!(equihash::debug_hash_offset(6) == 0, 2);

    // Indices 1, 4, 7, ... -> offset 18
    assert!(equihash::debug_hash_offset(1) == 18, 3);
    assert!(equihash::debug_hash_offset(4) == 18, 4);
    assert!(equihash::debug_hash_offset(7) == 18, 5);

    // Indices 2, 5, 8, ... -> offset 36
    assert!(equihash::debug_hash_offset(2) == 36, 6);
    assert!(equihash::debug_hash_offset(5) == 36, 7);
    assert!(equihash::debug_hash_offset(8) == 36, 8);
}

#[test]
/// Test debug_generate_hash produces correct length output
fun test_debug_generate_hash() {
    let input = x"0000000000000000000000000000000000000000000000000000000000000000";

    // Test various indices
    let hash_0 = equihash::debug_generate_hash(&input, 0);
    assert!(vector::length(&hash_0) == 18, 0);

    let hash_1 = equihash::debug_generate_hash(&input, 1);
    assert!(vector::length(&hash_1) == 18, 1);

    let hash_5 = equihash::debug_generate_hash(&input, 5);
    assert!(vector::length(&hash_5) == 18, 2);
}

#[test]
/// Test debug_expand_indices with zero solution
fun test_debug_expand_indices_zeros() {
    // Create 84-byte zero solution
    let mut solution = vector[];
    let mut i = 0;
    while (i < 84) {
        vector::push_back(&mut solution, 0u8);
        i = i + 1;
    };

    let indices = equihash::debug_expand_indices(&solution);
    assert!(vector::length(&indices) == 32, 0);

    // All indices should be 0
    let mut i = 0;
    while (i < 32) {
        assert!(*vector::borrow(&indices, i) == 0, i + 1);
        i = i + 1;
    };
}

#[test]
/// Test debug_generate_all_hashes produces correct number of hashes
fun test_debug_generate_all_hashes() {
    let input = x"0000000000000000000000000000000000000000000000000000000000000000";

    // Create indices vector [0, 1, 2, 3, 4]
    let mut indices = vector[];
    let mut i = 0;
    while (i < 5) {
        vector::push_back(&mut indices, (i as u32));
        i = i + 1;
    };

    let hashes = equihash::debug_generate_all_hashes(&input, &indices);
    assert!(vector::length(&hashes) == 5, 0);

    // Each hash should be 18 bytes
    let mut i = 0;
    while (i < 5) {
        let hash = vector::borrow(&hashes, i);
        assert!(vector::length(hash) == 18, i + 1);
        i = i + 1;
    };
}

#[test]
/// Test that indices in same block produce different hashes
fun test_same_block_different_hashes() {
    let input = x"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    // Indices 0, 1, 2 are in the same block but should produce different hashes
    let hash_0 = equihash::debug_generate_hash(&input, 0);
    let hash_1 = equihash::debug_generate_hash(&input, 1);
    let hash_2 = equihash::debug_generate_hash(&input, 2);

    // They should share the same block index
    assert!(equihash::debug_block_index(0) == equihash::debug_block_index(1), 0);
    assert!(equihash::debug_block_index(1) == equihash::debug_block_index(2), 1);

    // But have different offsets
    assert!(equihash::debug_hash_offset(0) != equihash::debug_hash_offset(1), 2);
    assert!(equihash::debug_hash_offset(1) != equihash::debug_hash_offset(2), 3);

    // And produce different hash values
    assert!(hash_0 != hash_1, 4);
    assert!(hash_1 != hash_2, 5);
    assert!(hash_0 != hash_2, 6);
}
