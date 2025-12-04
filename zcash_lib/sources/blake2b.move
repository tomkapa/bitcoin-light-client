// SPDX-License-Identifier: MPL-2.0

/// BLAKE2b-256 implementation with personalization support for Zcash/Equihash.
///
/// This is a pure Move implementation that supports the personalization parameter
/// required by Zcash's Equihash proof-of-work algorithm.
///
/// Reference: RFC 7693 - The BLAKE2 Cryptographic Hash and Message Authentication Code
module zcash_lib::blake2b;

/// BLAKE2b state for incremental hashing
public struct Blake2b has copy, drop {
    h: vector<u64>,      // 8 state words
    t: u128,             // byte counter
    buf: vector<u8>,     // 128-byte buffer
    buf_len: u64,        // bytes in buffer
    out_len: u8,         // output length (32 for BLAKE2b-256)
}

// ============================================================================
// Constants
// ============================================================================

// BLAKE2b IV (same as SHA-512 IV)
const IV0: u64 = 0x6A09E667F3BCC908;
const IV1: u64 = 0xBB67AE8584CAA73B;
const IV2: u64 = 0x3C6EF372FE94F82B;
const IV3: u64 = 0xA54FF53A5F1D36F1;
const IV4: u64 = 0x510E527FADE682D1;
const IV5: u64 = 0x9B05688C2B3E6C1F;
const IV6: u64 = 0x1F83D9ABFB41BD6B;
const IV7: u64 = 0x5BE0CD19137E2179;

// Rotation constants for BLAKE2b
const R1: u8 = 32;
const R2: u8 = 24;
const R3: u8 = 16;
const R4: u8 = 63;

// Number of 64-bit words in BLAKE2b state
const STATE_WORDS: u64 = 8;

// ============================================================================
// Public API
// ============================================================================

/// Create a new BLAKE2b-256 hasher with personalization.
///
/// For Equihash, use: personalization = "ZcashPoW" + LE32(n) + LE32(k)
/// where n=144, k=5 for testnet.
public fun new_with_personal(personalization: vector<u8>): Blake2b {
    new_with_personal_and_length(personalization, 32)
}

/// Create a new BLAKE2b hasher with personalization and custom output length.
/// output_len must be between 1 and 64 bytes.
public fun new_with_personal_and_length(personalization: vector<u8>, output_len: u8): Blake2b {
    assert!(vector::length(&personalization) <= 16, 0);
    assert!(output_len > 0 && output_len <= 64, 1);

    // Build parameter block (64 bytes)
    let mut param = create_zero_vector(64);
    *vector::borrow_mut(&mut param, 0) = output_len; // digest length
    *vector::borrow_mut(&mut param, 1) = 0;  // key length
    *vector::borrow_mut(&mut param, 2) = 1;  // fanout
    *vector::borrow_mut(&mut param, 3) = 1;  // depth

    // Copy personalization to bytes 48-63
    let plen = vector::length(&personalization);
    let mut i = 0;
    while (i < plen) {
        *vector::borrow_mut(&mut param, 48 + i) = *vector::borrow(&personalization, i);
        i = i + 1;
    };

    // Convert param block to 8 u64 words (little-endian)
    let p0 = read_le64(&param, 0);
    let p1 = read_le64(&param, 8);
    let p2 = read_le64(&param, 16);
    let p3 = read_le64(&param, 24);
    let p4 = read_le64(&param, 32);
    let p5 = read_le64(&param, 40);
    let p6 = read_le64(&param, 48);
    let p7 = read_le64(&param, 56);

    // XOR IV with parameter block
    let h = vector[
        IV0 ^ p0,
        IV1 ^ p1,
        IV2 ^ p2,
        IV3 ^ p3,
        IV4 ^ p4,
        IV5 ^ p5,
        IV6 ^ p6,
        IV7 ^ p7,
    ];

    Blake2b {
        h,
        t: 0,
        buf: create_zero_vector(128),
        buf_len: 0,
        out_len: output_len,
    }
}

/// Create a new BLAKE2b-256 hasher without personalization.
public fun new(): Blake2b {
    // h[0] = IV[0] ^ 0x01010000 ^ (kk << 8) ^ nn
    // where kk=0 (no key), nn=32 (output length)
    let h = vector[
        IV0 ^ 0x01010020, // 0x01010000 ^ 32
        IV1,
        IV2,
        IV3,
        IV4,
        IV5,
        IV6,
        IV7,
    ];

    Blake2b {
        h,
        t: 0,
        buf: create_zero_vector(128),
        buf_len: 0,
        out_len: 32,
    }
}

/// Update the hasher with more data.
public fun update(state: &mut Blake2b, data: &vector<u8>) {
    let data_len = vector::length(data);
    let mut data_idx = 0;

    // If we have buffered data and can fill a block
    if (state.buf_len > 0 && state.buf_len + data_len > 128) {
        // Fill buffer
        let fill = 128 - state.buf_len;
        let mut i = 0;
        while (i < fill) {
            *vector::borrow_mut(&mut state.buf, state.buf_len + i) = *vector::borrow(data, data_idx + i);
            i = i + 1;
        };
        state.t = state.t + 128;
        compress(state, false);
        state.buf_len = 0;
        data_idx = data_idx + fill;
    };

    // Process full blocks directly
    while (data_idx + 128 < data_len) {
        let mut i = 0;
        while (i < 128) {
            *vector::borrow_mut(&mut state.buf, i) = *vector::borrow(data, data_idx + i);
            i = i + 1;
        };
        state.t = state.t + 128;
        compress(state, false);
        data_idx = data_idx + 128;
    };

    // Buffer remaining data
    while (data_idx < data_len) {
        *vector::borrow_mut(&mut state.buf, state.buf_len) = *vector::borrow(data, data_idx);
        state.buf_len = state.buf_len + 1;
        data_idx = data_idx + 1;
    };
}

/// Finalize and return the hash with the configured output length.
public fun finalize(state: &mut Blake2b): vector<u8> {
    let output_len = state.out_len as u64;
    finalize_with_length(state, output_len)
}

/// Finalize and return hash with custom output length (1-64 bytes).
/// The output_len should match the configured state.out_len for BLAKE2b spec compliance.
public fun finalize_with_length(state: &mut Blake2b, output_len: u64): vector<u8> {
    assert!(output_len > 0 && output_len <= 64, 0);
    // Validate that output_len matches the configured digest length for spec compliance
    assert!(output_len == (state.out_len as u64), 1);

    // Update counter for final block
    state.t = state.t + (state.buf_len as u128);

    // Pad buffer with zeros
    let mut i = state.buf_len;
    while (i < 128) {
        *vector::borrow_mut(&mut state.buf, i) = 0;
        i = i + 1;
    };

    // Final compression
    compress(state, true);

    // Extract output (up to 64 bytes = STATE_WORDS * 8 bytes)
    let mut out = vector[];
    let mut bytes_extracted = 0;
    let mut word_idx = 0;

    while (bytes_extracted < output_len && word_idx < STATE_WORDS) {
        let word = *vector::borrow(&state.h, word_idx);
        let mut byte_in_word = 0;

        while (byte_in_word < 8 && bytes_extracted < output_len) {
            let byte_val = ((word >> (byte_in_word * 8)) & 0xff) as u8;
            vector::push_back(&mut out, byte_val);
            bytes_extracted = bytes_extracted + 1;
            byte_in_word = byte_in_word + 1;
        };

        word_idx = word_idx + 1;
    };

    out
}

/// One-shot hash with personalization.
public fun hash_with_personal(data: &vector<u8>, personalization: vector<u8>): vector<u8> {
    let mut state = new_with_personal(personalization);
    update(&mut state, data);
    finalize(&mut state)
}

/// One-shot hash with personalization and custom output length.
/// Supports output lengths from 1 to 64 bytes.
public fun hash_with_personal_and_length(
    data: &vector<u8>,
    personalization: vector<u8>,
    output_len: u64
): vector<u8> {
    assert!(output_len > 0 && output_len <= 64, 0);
    let mut state = new_with_personal_and_length(personalization, (output_len as u8));
    update(&mut state, data);
    finalize_with_length(&mut state, output_len)
}

/// One-shot hash without personalization.
public fun hash(data: &vector<u8>): vector<u8> {
    let mut state = new();
    update(&mut state, data);
    finalize(&mut state)
}

/// Build Equihash personalization string: "ZcashPoW" + LE32(n) + LE32(k)
public fun equihash_personal(n: u32, k: u32): vector<u8> {
    let mut p = b"ZcashPoW";
    // Append n as little-endian u32
    vector::push_back(&mut p, (n & 0xff) as u8);
    vector::push_back(&mut p, ((n >> 8) & 0xff) as u8);
    vector::push_back(&mut p, ((n >> 16) & 0xff) as u8);
    vector::push_back(&mut p, ((n >> 24) & 0xff) as u8);
    // Append k as little-endian u32
    vector::push_back(&mut p, (k & 0xff) as u8);
    vector::push_back(&mut p, ((k >> 8) & 0xff) as u8);
    vector::push_back(&mut p, ((k >> 16) & 0xff) as u8);
    vector::push_back(&mut p, ((k >> 24) & 0xff) as u8);
    p
}

// ============================================================================
// Internal: Compression Function
// ============================================================================

/// BLAKE2b compression function F.
fun compress(state: &mut Blake2b, is_final: bool) {
    // Initialize working vector v[0..15]
    let mut v = vector[
        *vector::borrow(&state.h, 0), *vector::borrow(&state.h, 1),
        *vector::borrow(&state.h, 2), *vector::borrow(&state.h, 3),
        *vector::borrow(&state.h, 4), *vector::borrow(&state.h, 5),
        *vector::borrow(&state.h, 6), *vector::borrow(&state.h, 7),
        IV0, IV1, IV2, IV3, IV4, IV5, IV6, IV7,
    ];

    // XOR counter into v[12..13]
    let t_lo = (state.t & 0xffffffffffffffff) as u64;
    let t_hi = ((state.t >> 64) & 0xffffffffffffffff) as u64;
    *vector::borrow_mut(&mut v, 12) = *vector::borrow(&v, 12) ^ t_lo;
    *vector::borrow_mut(&mut v, 13) = *vector::borrow(&v, 13) ^ t_hi;

    // Invert v[14] if final block
    if (is_final) {
        *vector::borrow_mut(&mut v, 14) = *vector::borrow(&v, 14) ^ 0xffffffffffffffff;
    };

    // Parse message block into 16 words
    let m = vector[
        read_le64(&state.buf, 0),
        read_le64(&state.buf, 8),
        read_le64(&state.buf, 16),
        read_le64(&state.buf, 24),
        read_le64(&state.buf, 32),
        read_le64(&state.buf, 40),
        read_le64(&state.buf, 48),
        read_le64(&state.buf, 56),
        read_le64(&state.buf, 64),
        read_le64(&state.buf, 72),
        read_le64(&state.buf, 80),
        read_le64(&state.buf, 88),
        read_le64(&state.buf, 96),
        read_le64(&state.buf, 104),
        read_le64(&state.buf, 112),
        read_le64(&state.buf, 120),
    ];

    // 12 rounds of mixing
    // Round 0: SIGMA[0]
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 0), *vector::borrow(&m, 1));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 2), *vector::borrow(&m, 3));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 4), *vector::borrow(&m, 5));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 6), *vector::borrow(&m, 7));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 8), *vector::borrow(&m, 9));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 10), *vector::borrow(&m, 11));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 12), *vector::borrow(&m, 13));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 14), *vector::borrow(&m, 15));

    // Round 1: SIGMA[1] = 14 10 4 8 9 15 13 6 1 12 0 2 11 7 5 3
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 14), *vector::borrow(&m, 10));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 4), *vector::borrow(&m, 8));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 9), *vector::borrow(&m, 15));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 13), *vector::borrow(&m, 6));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 1), *vector::borrow(&m, 12));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 0), *vector::borrow(&m, 2));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 11), *vector::borrow(&m, 7));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 5), *vector::borrow(&m, 3));

    // Round 2: SIGMA[2] = 11 8 12 0 5 2 15 13 10 14 3 6 7 1 9 4
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 11), *vector::borrow(&m, 8));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 12), *vector::borrow(&m, 0));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 5), *vector::borrow(&m, 2));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 15), *vector::borrow(&m, 13));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 10), *vector::borrow(&m, 14));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 3), *vector::borrow(&m, 6));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 7), *vector::borrow(&m, 1));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 9), *vector::borrow(&m, 4));

    // Round 3: SIGMA[3] = 7 9 3 1 13 12 11 14 2 6 5 10 4 0 15 8
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 7), *vector::borrow(&m, 9));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 3), *vector::borrow(&m, 1));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 13), *vector::borrow(&m, 12));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 11), *vector::borrow(&m, 14));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 2), *vector::borrow(&m, 6));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 5), *vector::borrow(&m, 10));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 4), *vector::borrow(&m, 0));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 15), *vector::borrow(&m, 8));

    // Round 4: SIGMA[4] = 9 0 5 7 2 4 10 15 14 1 11 12 6 8 3 13
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 9), *vector::borrow(&m, 0));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 5), *vector::borrow(&m, 7));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 2), *vector::borrow(&m, 4));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 10), *vector::borrow(&m, 15));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 14), *vector::borrow(&m, 1));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 11), *vector::borrow(&m, 12));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 6), *vector::borrow(&m, 8));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 3), *vector::borrow(&m, 13));

    // Round 5: SIGMA[5] = 2 12 6 10 0 11 8 3 4 13 7 5 15 14 1 9
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 2), *vector::borrow(&m, 12));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 6), *vector::borrow(&m, 10));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 0), *vector::borrow(&m, 11));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 8), *vector::borrow(&m, 3));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 4), *vector::borrow(&m, 13));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 7), *vector::borrow(&m, 5));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 15), *vector::borrow(&m, 14));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 1), *vector::borrow(&m, 9));

    // Round 6: SIGMA[6] = 12 5 1 15 14 13 4 10 0 7 6 3 9 2 8 11
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 12), *vector::borrow(&m, 5));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 1), *vector::borrow(&m, 15));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 14), *vector::borrow(&m, 13));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 4), *vector::borrow(&m, 10));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 0), *vector::borrow(&m, 7));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 6), *vector::borrow(&m, 3));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 9), *vector::borrow(&m, 2));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 8), *vector::borrow(&m, 11));

    // Round 7: SIGMA[7] = 13 11 7 14 12 1 3 9 5 0 15 4 8 6 2 10
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 13), *vector::borrow(&m, 11));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 7), *vector::borrow(&m, 14));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 12), *vector::borrow(&m, 1));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 3), *vector::borrow(&m, 9));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 5), *vector::borrow(&m, 0));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 15), *vector::borrow(&m, 4));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 8), *vector::borrow(&m, 6));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 2), *vector::borrow(&m, 10));

    // Round 8: SIGMA[8] = 6 15 14 9 11 3 0 8 12 2 13 7 1 4 10 5
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 6), *vector::borrow(&m, 15));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 14), *vector::borrow(&m, 9));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 11), *vector::borrow(&m, 3));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 0), *vector::borrow(&m, 8));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 12), *vector::borrow(&m, 2));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 13), *vector::borrow(&m, 7));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 1), *vector::borrow(&m, 4));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 10), *vector::borrow(&m, 5));

    // Round 9: SIGMA[9] = 10 2 8 4 7 6 1 5 15 11 9 14 3 12 13 0
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 10), *vector::borrow(&m, 2));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 8), *vector::borrow(&m, 4));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 7), *vector::borrow(&m, 6));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 1), *vector::borrow(&m, 5));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 15), *vector::borrow(&m, 11));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 9), *vector::borrow(&m, 14));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 3), *vector::borrow(&m, 12));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 13), *vector::borrow(&m, 0));

    // Round 10: SIGMA[0] (repeat)
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 0), *vector::borrow(&m, 1));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 2), *vector::borrow(&m, 3));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 4), *vector::borrow(&m, 5));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 6), *vector::borrow(&m, 7));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 8), *vector::borrow(&m, 9));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 10), *vector::borrow(&m, 11));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 12), *vector::borrow(&m, 13));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 14), *vector::borrow(&m, 15));

    // Round 11: SIGMA[1] (repeat)
    mix(&mut v, 0, 4, 8, 12, *vector::borrow(&m, 14), *vector::borrow(&m, 10));
    mix(&mut v, 1, 5, 9, 13, *vector::borrow(&m, 4), *vector::borrow(&m, 8));
    mix(&mut v, 2, 6, 10, 14, *vector::borrow(&m, 9), *vector::borrow(&m, 15));
    mix(&mut v, 3, 7, 11, 15, *vector::borrow(&m, 13), *vector::borrow(&m, 6));
    mix(&mut v, 0, 5, 10, 15, *vector::borrow(&m, 1), *vector::borrow(&m, 12));
    mix(&mut v, 1, 6, 11, 12, *vector::borrow(&m, 0), *vector::borrow(&m, 2));
    mix(&mut v, 2, 7, 8, 13, *vector::borrow(&m, 11), *vector::borrow(&m, 7));
    mix(&mut v, 3, 4, 9, 14, *vector::borrow(&m, 5), *vector::borrow(&m, 3));

    // Finalize: h[i] = h[i] ^ v[i] ^ v[i+8]
    *vector::borrow_mut(&mut state.h, 0) = *vector::borrow(&state.h, 0) ^ *vector::borrow(&v, 0) ^ *vector::borrow(&v, 8);
    *vector::borrow_mut(&mut state.h, 1) = *vector::borrow(&state.h, 1) ^ *vector::borrow(&v, 1) ^ *vector::borrow(&v, 9);
    *vector::borrow_mut(&mut state.h, 2) = *vector::borrow(&state.h, 2) ^ *vector::borrow(&v, 2) ^ *vector::borrow(&v, 10);
    *vector::borrow_mut(&mut state.h, 3) = *vector::borrow(&state.h, 3) ^ *vector::borrow(&v, 3) ^ *vector::borrow(&v, 11);
    *vector::borrow_mut(&mut state.h, 4) = *vector::borrow(&state.h, 4) ^ *vector::borrow(&v, 4) ^ *vector::borrow(&v, 12);
    *vector::borrow_mut(&mut state.h, 5) = *vector::borrow(&state.h, 5) ^ *vector::borrow(&v, 5) ^ *vector::borrow(&v, 13);
    *vector::borrow_mut(&mut state.h, 6) = *vector::borrow(&state.h, 6) ^ *vector::borrow(&v, 6) ^ *vector::borrow(&v, 14);
    *vector::borrow_mut(&mut state.h, 7) = *vector::borrow(&state.h, 7) ^ *vector::borrow(&v, 7) ^ *vector::borrow(&v, 15);
}

/// G mixing function: mixes words at positions a, b, c, d with message words x, y.
fun mix(v: &mut vector<u64>, a: u64, b: u64, c: u64, d: u64, x: u64, y: u64) {
    let va = *vector::borrow(v, a);
    let vb = *vector::borrow(v, b);
    let vc = *vector::borrow(v, c);
    let vd = *vector::borrow(v, d);

    // v[a] = v[a] + v[b] + x
    let va = wrapping_add(wrapping_add(va, vb), x);
    // v[d] = rotr64(v[d] ^ v[a], 32)
    let vd = rotr64(vd ^ va, R1);
    // v[c] = v[c] + v[d]
    let vc = wrapping_add(vc, vd);
    // v[b] = rotr64(v[b] ^ v[c], 24)
    let vb = rotr64(vb ^ vc, R2);

    // v[a] = v[a] + v[b] + y
    let va = wrapping_add(wrapping_add(va, vb), y);
    // v[d] = rotr64(v[d] ^ v[a], 16)
    let vd = rotr64(vd ^ va, R3);
    // v[c] = v[c] + v[d]
    let vc = wrapping_add(vc, vd);
    // v[b] = rotr64(v[b] ^ v[c], 63)
    let vb = rotr64(vb ^ vc, R4);

    *vector::borrow_mut(v, a) = va;
    *vector::borrow_mut(v, b) = vb;
    *vector::borrow_mut(v, c) = vc;
    *vector::borrow_mut(v, d) = vd;
}

// ============================================================================
// Internal: Helper Functions
// ============================================================================

/// Create a vector of zeros with the given length.
fun create_zero_vector(len: u64): vector<u8> {
    let mut v = vector[];
    let mut i = 0;
    while (i < len) {
        vector::push_back(&mut v, 0u8);
        i = i + 1;
    };
    v
}

/// 64-bit right rotation.
fun rotr64(x: u64, n: u8): u64 {
    (x >> n) | (x << (64 - n))
}

/// Wrapping addition for u64 (handles overflow).
fun wrapping_add(a: u64, b: u64): u64 {
    let sum = (a as u128) + (b as u128);
    (sum & 0xffffffffffffffff) as u64
}

/// Read little-endian u64 from bytes at offset.
fun read_le64(data: &vector<u8>, offset: u64): u64 {
    let b0 = *vector::borrow(data, offset) as u64;
    let b1 = *vector::borrow(data, offset + 1) as u64;
    let b2 = *vector::borrow(data, offset + 2) as u64;
    let b3 = *vector::borrow(data, offset + 3) as u64;
    let b4 = *vector::borrow(data, offset + 4) as u64;
    let b5 = *vector::borrow(data, offset + 5) as u64;
    let b6 = *vector::borrow(data, offset + 6) as u64;
    let b7 = *vector::borrow(data, offset + 7) as u64;

    b0 | (b1 << 8) | (b2 << 16) | (b3 << 24) |
    (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56)
}

// ============================================================================
// Tests
// ============================================================================

#[test]
/// Test vector: BLAKE2b-256 of empty string (no personalization)
/// Expected: 0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8
fun test_blake2b_empty() {
    let data = vector[];
    let hash = hash(&data);
    let expected = x"0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8";
    assert!(hash == expected, 1);
}

#[test]
/// Test vector: BLAKE2b-256 of "abc" (no personalization)
/// Expected: bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319
fun test_blake2b_abc() {
    let data = b"abc";
    let hash = hash(&data);
    let expected = x"bddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319";
    assert!(hash == expected, 2);
}

#[test]
/// Test BLAKE2b-256 with personalization.
fun test_blake2b_with_personalization() {
    let personal = b"MyPersonalStr\x00\x00\x00"; // 16 bytes
    let data = b"test";
    let hash = hash_with_personal(&data, personal);
    assert!(vector::length(&hash) == 32, 0);
}

#[test]
/// Test Equihash personalization format for testnet (n=144, k=5)
fun test_equihash_personalization_format() {
    let personal = equihash_personal(144, 5);
    assert!(vector::length(&personal) == 16, 0);
    let expected = x"5a63617368506f579000000005000000";
    assert!(personal == expected, 3);
}

#[test]
/// Test longer message (multi-block)
fun test_blake2b_long_message() {
    let mut data = vector[];
    let mut i = 0;
    while (i < 200) {
        vector::push_back(&mut data, 97u8);
        i = i + 1;
    };
    let hash = hash(&data);
    assert!(vector::length(&hash) == 32, 0);
}
