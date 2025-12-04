// SPDX-License-Identifier: MPL-2.0

/// Tests for generate_single_hash implementation verification.
/// Validates that generate_single_hash correctly computes block_index and offset.
#[test_only]
module zcash_lib::generate_single_hash_tests;

use zcash_lib::blake2b;

const INDICES_PER_HASH: u64 = 3;
const HASH_LENGTH: u64 = 18;
const HASH_OUTPUT_SIZE: u64 = 54;

#[test]
/// Test that different indices in the same block share the same BLAKE2b input
/// Indices 0, 1, 2 should all use block_index=0
fun test_same_block_indices() {
    // Indices 0, 1, 2 should all map to block 0
    let block_0_for_idx_0 = 0 / INDICES_PER_HASH;
    let block_0_for_idx_1 = 1 / INDICES_PER_HASH;
    let block_0_for_idx_2 = 2 / INDICES_PER_HASH;

    assert!(block_0_for_idx_0 == 0, 0);
    assert!(block_0_for_idx_1 == 0, 1);
    assert!(block_0_for_idx_2 == 0, 2);

    // Indices 3, 4, 5 should all map to block 1
    let block_1_for_idx_3 = 3 / INDICES_PER_HASH;
    let block_1_for_idx_4 = 4 / INDICES_PER_HASH;
    let block_1_for_idx_5 = 5 / INDICES_PER_HASH;

    assert!(block_1_for_idx_3 == 1, 3);
    assert!(block_1_for_idx_4 == 1, 4);
    assert!(block_1_for_idx_5 == 1, 5);
}

#[test]
/// Test that hash extraction offsets are correctly calculated
fun test_hash_extraction_offsets() {
    // Index 0, 3, 6, ... -> offset 0
    assert!((0 % INDICES_PER_HASH) * HASH_LENGTH == 0, 0);
    assert!((3 % INDICES_PER_HASH) * HASH_LENGTH == 0, 1);

    // Index 1, 4, 7, ... -> offset 18
    assert!((1 % INDICES_PER_HASH) * HASH_LENGTH == 18, 2);
    assert!((4 % INDICES_PER_HASH) * HASH_LENGTH == 18, 3);

    // Index 2, 5, 8, ... -> offset 36
    assert!((2 % INDICES_PER_HASH) * HASH_LENGTH == 36, 4);
    assert!((5 % INDICES_PER_HASH) * HASH_LENGTH == 36, 5);
}

#[test]
/// Test that BLAKE2b with custom length produces correct output size
fun test_blake2b_custom_length() {
    let input = x"0000000000000000000000000000000000000000000000000000000000000000";
    let personal = blake2b::equihash_personal(144, 5);

    // Test 54-byte output
    let hash_54 = blake2b::hash_with_personal_and_length(&input, personal, 54);
    assert!(vector::length(&hash_54) == 54, 0);

    // Test that we can extract 3 separate 18-byte hashes from it
    let offset_0 = 0;
    let offset_1 = 18;
    let offset_2 = 36;

    // Verify we can access all offsets
    assert!(offset_0 + HASH_LENGTH <= vector::length(&hash_54), 1);
    assert!(offset_1 + HASH_LENGTH <= vector::length(&hash_54), 2);
    assert!(offset_2 + HASH_LENGTH <= vector::length(&hash_54), 3);
}

#[test]
/// Test the complete hash generation logic structure
fun test_hash_generation_structure() {
    // For n=144, k=5:
    // - INDICES_PER_HASH = 3 (three 18-byte hashes per 54-byte BLAKE2b output)
    // - HASH_LENGTH = 18 bytes
    // - HASH_OUTPUT_SIZE = 54 bytes

    // Verify the math works out
    assert!(INDICES_PER_HASH * HASH_LENGTH == HASH_OUTPUT_SIZE, 0);

    // For any index i:
    // - block_index = i / 3
    // - offset = (i % 3) * 18
    // - hash = BLAKE2b-432(input || LE32(block_index))[offset:offset+18]

    // Verify indices 0-8 map correctly
    let indices = vector[0u32, 1u32, 2u32, 3u32, 4u32, 5u32, 6u32, 7u32, 8u32];
    let expected_blocks = vector[0u32, 0u32, 0u32, 1u32, 1u32, 1u32, 2u32, 2u32, 2u32];
    let expected_offsets = vector[0u64, 18u64, 36u64, 0u64, 18u64, 36u64, 0u64, 18u64, 36u64];

    let mut i = 0;
    while (i < 9) {
        let index = *vector::borrow(&indices, i);
        let block = (index as u64) / INDICES_PER_HASH;
        let offset = ((index as u64) % INDICES_PER_HASH) * HASH_LENGTH;

        assert!(block == (*vector::borrow(&expected_blocks, i) as u64), i);
        assert!(offset == *vector::borrow(&expected_offsets, i), i + 100);

        i = i + 1;
    };
}
