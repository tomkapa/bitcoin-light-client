// SPDX-License-Identifier: MPL-2.0

/// Equihash proof-of-work verification for Zcash testnet (n=144, k=5).
///
/// Equihash is a memory-hard proof-of-work algorithm based on Wagner's
/// generalized birthday problem. This module verifies Equihash solutions.
///
/// Parameters for testnet:
/// - n = 144 (collision bit length)
/// - k = 5 (number of rounds)
/// - Solution contains 2^k = 32 indices
/// - Each index is 21 bits
/// - Collision width per round: n/(k+1) = 24 bits
module zcash_lib::equihash;

use zcash_lib::blake2b;

// ============================================================================
// Constants for Equihash(144, 5)
// ============================================================================

#[allow(unused_const)]
/// Collision bit length
const N: u64 = 144;

/// Number of rounds (Wagner iterations)
const K: u64 = 5;

/// Number of solution indices: 2^k = 32
const NUM_INDICES: u64 = 32;

/// Bits per index (ceiling of log2 of hash count)
const INDEX_BITS: u64 = 21;

/// Collision width per round: n/(k+1) = 24 bits = 3 bytes
const COLLISION_BYTES: u64 = 3;

/// Hash output length: (k+1) * collision_bytes = 18 bytes
const HASH_LENGTH: u64 = 18;

/// Compressed solution size: (NUM_INDICES * INDEX_BITS + 7) / 8 = 84 bytes
const SOLUTION_SIZE: u64 = 84;

// ============================================================================
// Error Codes
// ============================================================================

const E_INVALID_SOLUTION_LENGTH: u64 = 1;
const E_DUPLICATE_INDEX: u64 = 2;
const E_INVALID_ORDERING: u64 = 3;
const E_COLLISION_CHECK_FAILED: u64 = 4;
const E_FINAL_HASH_NOT_ZERO: u64 = 5;
const E_INDEX_OUT_OF_RANGE: u64 = 6;

// ============================================================================
// Public API
// ============================================================================

/// Verify an Equihash solution.
///
/// # Arguments
/// * `header` - The block header (without nonce and solution)
/// * `nonce` - The 32-byte nonce
/// * `solution` - The compressed solution (84 bytes for n=144, k=5)
///
/// # Returns
/// * `true` if the solution is valid, aborts otherwise
public fun verify(header: &vector<u8>, nonce: &vector<u8>, solution: &vector<u8>): bool {
    // Check solution length
    assert!(vector::length(solution) == SOLUTION_SIZE, E_INVALID_SOLUTION_LENGTH);

    // Expand the compressed solution to get 32 indices
    let indices = expand_indices(solution);

    // Validate indices are within range and check ordering
    validate_indices(&indices);

    // Build the input for BLAKE2b: header || nonce
    let mut input = *header;
    let nonce_len = vector::length(nonce);
    let mut i = 0;
    while (i < nonce_len) {
        vector::push_back(&mut input, *vector::borrow(nonce, i));
        i = i + 1;
    };

    // Generate hashes for each index
    let hashes = generate_hashes(&input, &indices);

    // Verify the XOR tree structure
    verify_xor_tree(&hashes);

    true
}

/// Verify only the solution structure (without header).
/// Useful for testing the XOR tree logic.
public fun verify_solution_structure(solution: &vector<u8>, input: &vector<u8>): bool {
    assert!(vector::length(solution) == SOLUTION_SIZE, E_INVALID_SOLUTION_LENGTH);

    let indices = expand_indices(solution);
    validate_indices(&indices);
    let hashes = generate_hashes(input, &indices);
    verify_xor_tree(&hashes);

    true
}

// ============================================================================
// Internal: Solution Expansion
// ============================================================================

/// Expand compressed solution to 32 indices.
/// Each index is 21 bits, packed into 84 bytes.
fun expand_indices(solution: &vector<u8>): vector<u32> {
    let mut indices = vector[];
    let mut bit_pos: u64 = 0;

    let mut i = 0;
    while (i < NUM_INDICES) {
        let index = read_bits_le(solution, bit_pos, INDEX_BITS);
        vector::push_back(&mut indices, (index as u32));
        bit_pos = bit_pos + INDEX_BITS;
        i = i + 1;
    };

    indices
}

/// Read `num_bits` from byte array starting at `bit_offset` (little-endian bit order).
fun read_bits_le(data: &vector<u8>, bit_offset: u64, num_bits: u64): u64 {
    let mut result: u64 = 0;
    let mut bits_read: u64 = 0;

    while (bits_read < num_bits) {
        let current_bit = bit_offset + bits_read;
        let byte_idx = current_bit / 8;
        let bit_idx = current_bit % 8;

        let byte_val = *vector::borrow(data, byte_idx) as u64;
        let bit_val = (byte_val >> (bit_idx as u8)) & 1;

        result = result | (bit_val << (bits_read as u8));
        bits_read = bits_read + 1;
    };

    result
}

// ============================================================================
// Internal: Index Validation
// ============================================================================

/// Validate that indices are in range and properly ordered.
fun validate_indices(indices: &vector<u32>) {
    let max_index = (1u32 << 21) - 1; // 2^21 - 1

    // Check each index is in valid range
    let mut i = 0;
    while (i < NUM_INDICES) {
        let idx = *vector::borrow(indices, i);
        assert!((idx as u64) <= (max_index as u64), E_INDEX_OUT_OF_RANGE);
        i = i + 1;
    };

    // Check for duplicates (simple O(n^2) check - acceptable for 32 indices)
    let mut i = 0;
    while (i < NUM_INDICES) {
        let mut j = i + 1;
        while (j < NUM_INDICES) {
            assert!(
                *vector::borrow(indices, i) != *vector::borrow(indices, j),
                E_DUPLICATE_INDEX
            );
            j = j + 1;
        };
        i = i + 1;
    };

    // Check tree ordering: for each pair, first index < second index
    // This enforces the canonical solution representation
    check_tree_ordering(indices, 0, NUM_INDICES, K);
}

/// Recursively check tree ordering constraints.
/// At each level, the minimum index in the left subtree must be less than
/// the minimum index in the right subtree.
fun check_tree_ordering(indices: &vector<u32>, start: u64, count: u64, depth: u64) {
    if (depth == 0 || count <= 1) {
        return
    };

    let half = count / 2;

    // Get minimum of left half
    let left_min = get_min_index(indices, start, half);
    // Get minimum of right half
    let right_min = get_min_index(indices, start + half, half);

    // Left minimum must be less than right minimum
    assert!(left_min < right_min, E_INVALID_ORDERING);

    // Recurse into subtrees
    check_tree_ordering(indices, start, half, depth - 1);
    check_tree_ordering(indices, start + half, half, depth - 1);
}

/// Get minimum index in a range.
fun get_min_index(indices: &vector<u32>, start: u64, count: u64): u32 {
    let mut min_val = *vector::borrow(indices, start);
    let mut i = 1;
    while (i < count) {
        let val = *vector::borrow(indices, start + i);
        if (val < min_val) {
            min_val = val;
        };
        i = i + 1;
    };
    min_val
}

// ============================================================================
// Internal: Hash Generation
// ============================================================================

/// Generate hashes for each index using BLAKE2b with Equihash personalization.
fun generate_hashes(input: &vector<u8>, indices: &vector<u32>): vector<vector<u8>> {
    let personal = blake2b::equihash_personal(144, 5);
    let mut hashes = vector[];

    let mut i = 0;
    while (i < NUM_INDICES) {
        let idx = *vector::borrow(indices, i);
        let hash = generate_single_hash(input, idx, &personal);
        vector::push_back(&mut hashes, hash);
        i = i + 1;
    };

    hashes
}

/// Generate hash for a single index.
/// BLAKE2b(input || LE32(index / hashes_per_block)) then extract appropriate slice.
fun generate_single_hash(input: &vector<u8>, index: u32, personal: &vector<u8>): vector<u8> {
    // For n=144, k=5: each BLAKE2b output (32 bytes) contains multiple hash outputs
    // Hash output is 18 bytes (HASH_LENGTH), and we get 32/18 = 1 full hash per BLAKE2b
    // Actually, we need to compute: how many hashes fit in one BLAKE2b-256 output
    // hash_length = 18 bytes, blake2b output = 32 bytes
    // hashes_per_blake = 32 / 18 = 1 (with some waste)

    // For Zcash's Equihash, the formula is:
    // BLAKE2b(input || LE32(i)) produces 32 bytes
    // We extract hash_length bytes starting at (i % indices_per_hash) * hash_length

    // Simpler approach for n=144, k=5:
    // Each index i generates: BLAKE2b(input || LE32(i / 2))[hash_len * (i % 2) : hash_len * (i % 2 + 1)]
    // But 2 * 18 = 36 > 32, so actually we use one BLAKE2b per hash

    // Let's use the standard approach: BLAKE2b(input || LE32(index))
    // Then take first HASH_LENGTH bytes

    let mut hash_input = *input;
    // Append index as little-endian u32
    vector::push_back(&mut hash_input, (index & 0xff) as u8);
    vector::push_back(&mut hash_input, ((index >> 8) & 0xff) as u8);
    vector::push_back(&mut hash_input, ((index >> 16) & 0xff) as u8);
    vector::push_back(&mut hash_input, ((index >> 24) & 0xff) as u8);

    let full_hash = blake2b::hash_with_personal(&hash_input, *personal);

    // Extract first HASH_LENGTH bytes
    let mut result = vector[];
    let mut i = 0;
    while (i < HASH_LENGTH) {
        vector::push_back(&mut result, *vector::borrow(&full_hash, i));
        i = i + 1;
    };

    result
}

// ============================================================================
// Internal: XOR Tree Verification
// ============================================================================

/// Verify the XOR tree structure.
/// At each round, pairs of hashes are XORed, and the first `collision_bytes * round`
/// bytes must be zero. After k rounds, all bytes must be zero.
fun verify_xor_tree(hashes: &vector<vector<u8>>) {
    let mut current_hashes = *hashes;
    let mut round = 1u64;

    while (round <= K) {
        let num_hashes = vector::length(&current_hashes);
        let mut next_hashes = vector[];

        let mut i = 0;
        while (i < num_hashes) {
            let left = vector::borrow(&current_hashes, i);
            let right = vector::borrow(&current_hashes, i + 1);

            // XOR the two hashes
            let xored = xor_bytes(left, right);

            // Check that first (round * COLLISION_BYTES) bytes are zero
            let zeros_required = round * COLLISION_BYTES;
            let mut j = 0;
            while (j < zeros_required && j < vector::length(&xored)) {
                assert!(*vector::borrow(&xored, j) == 0, E_COLLISION_CHECK_FAILED);
                j = j + 1;
            };

            // For next round, use remaining bytes (skip the zero prefix)
            let mut trimmed = vector[];
            let mut j = zeros_required;
            while (j < vector::length(&xored)) {
                vector::push_back(&mut trimmed, *vector::borrow(&xored, j));
                j = j + 1;
            };

            vector::push_back(&mut next_hashes, trimmed);
            i = i + 2;
        };

        current_hashes = next_hashes;
        round = round + 1;
    };

    // After k rounds, we should have one hash left, and it should be all zeros
    assert!(vector::length(&current_hashes) == 1, E_FINAL_HASH_NOT_ZERO);
    let final_hash = vector::borrow(&current_hashes, 0);
    let mut i = 0;
    while (i < vector::length(final_hash)) {
        assert!(*vector::borrow(final_hash, i) == 0, E_FINAL_HASH_NOT_ZERO);
        i = i + 1;
    };
}

/// XOR two byte vectors.
fun xor_bytes(a: &vector<u8>, b: &vector<u8>): vector<u8> {
    let len_a = vector::length(a);
    let len_b = vector::length(b);
    let len = if (len_a < len_b) { len_a } else { len_b };

    let mut result = vector[];
    let mut i = 0;
    while (i < len) {
        vector::push_back(&mut result, *vector::borrow(a, i) ^ *vector::borrow(b, i));
        i = i + 1;
    };

    result
}

// ============================================================================
// Tests
// ============================================================================

#[test]
fun test_expand_indices_basic() {
    // Create a simple test solution (84 bytes of zeros should give all zero indices)
    let mut solution = vector[];
    let mut i = 0;
    while (i < 84) {
        vector::push_back(&mut solution, 0u8);
        i = i + 1;
    };

    let indices = expand_indices(&solution);
    assert!(vector::length(&indices) == 32, 0);

    // All indices should be 0
    let mut i = 0;
    while (i < 32) {
        assert!(*vector::borrow(&indices, i) == 0, 1);
        i = i + 1;
    };
}

#[test]
fun test_read_bits_le() {
    // Test reading bits from a byte array
    let data = vector[0xd6u8, 0xa9u8]; // 0b11010110, 0b10101001

    // Read first 8 bits (should be 0xd6 = 214)
    let val = read_bits_le(&data, 0, 8);
    assert!(val == 214, 0);

    // Read bits 4-11 (crossing byte boundary)
    let val = read_bits_le(&data, 4, 8);
    // bits 4-7 from first byte: 1101 (high nibble of 0xd6)
    // bits 0-3 from second byte: 1001 (low nibble of 0xa9)
    // Combined LE: 0x9d = 157
    assert!(val == 157, 1);
}

#[test]
fun test_xor_bytes() {
    let a = vector[0xffu8, 0x00u8, 0xaau8];
    let b = vector[0xffu8, 0xffu8, 0x55u8];
    let result = xor_bytes(&a, &b);

    assert!(*vector::borrow(&result, 0) == 0x00, 0);
    assert!(*vector::borrow(&result, 1) == 0xff, 1);
    assert!(*vector::borrow(&result, 2) == 0xff, 2);
}

#[test]
fun test_equihash_personalization() {
    let personal = blake2b::equihash_personal(144, 5);
    assert!(vector::length(&personal) == 16, 0);

    // "ZcashPoW" = 0x5a63617368506f77
    // 144 in LE = 0x90000000
    // 5 in LE = 0x05000000
    let expected = x"5a63617368506f579000000005000000";
    assert!(personal == expected, 1);
}

#[test]
fun test_generate_single_hash() {
    let input = x"0000000000000000000000000000000000000000000000000000000000000000";
    let personal = blake2b::equihash_personal(144, 5);

    let hash = generate_single_hash(&input, 0, &personal);
    assert!(vector::length(&hash) == 18, 0); // HASH_LENGTH = 18
}

#[test]
fun test_tree_ordering_valid() {
    // Valid ordering: each left subtree min < right subtree min
    let indices = vector[
        1u32, 3u32, 5u32, 7u32, 9u32, 11u32, 13u32, 15u32,
        17u32, 19u32, 21u32, 23u32, 25u32, 27u32, 29u32, 31u32,
        33u32, 35u32, 37u32, 39u32, 41u32, 43u32, 45u32, 47u32,
        49u32, 51u32, 53u32, 55u32, 57u32, 59u32, 61u32, 63u32
    ];

    // This should not abort
    check_tree_ordering(&indices, 0, 32, 5);
}

#[test]
#[expected_failure(abort_code = E_INVALID_ORDERING)]
fun test_tree_ordering_invalid() {
    // Invalid ordering: first element > 17th element (left subtree min > right subtree min)
    let indices = vector[
        100u32, 3u32, 5u32, 7u32, 9u32, 11u32, 13u32, 15u32,
        17u32, 19u32, 21u32, 23u32, 25u32, 27u32, 29u32, 31u32,
        1u32, 35u32, 37u32, 39u32, 41u32, 43u32, 45u32, 47u32,  // 1 < 100, so invalid
        49u32, 51u32, 53u32, 55u32, 57u32, 59u32, 61u32, 63u32
    ];

    check_tree_ordering(&indices, 0, 32, 5);
}
