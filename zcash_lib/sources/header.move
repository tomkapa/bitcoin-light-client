// SPDX-License-Identifier: MPL-2.0

module zcash_lib::header;

use bitcoin_lib::crypto::hash256;
use bitcoin_lib::reader;

// === Constants ===
const BLOCK_HEADER_SIZE: u64 = 140;
const TESTNET_SOLUTION_SIZE: u64 = 100;
const MAINNET_SOLUTION_SIZE: u64 = 1344;

#[error]
const EInvalidBlockHeaderSize: vector<u8> = b"The block header must be exactly 140 bytes long";

public struct BlockHeader has copy, drop, store {
    version: u32,
    parent: vector<u8>,
    merkle_root: vector<u8>,
    hash_reserved: vector<u8>,
    timestamp: u32,
    bits: u32,
    nonce: vector<u8>,
    solution: vector<u8>,
    block_hash: vector<u8>,
}

// === Block header methods ===

/// New block header from raw 140-byte header (without solution)
public fun new(raw_block_header: vector<u8>): BlockHeader {
    assert!(raw_block_header.length() == BLOCK_HEADER_SIZE, EInvalidBlockHeaderSize);

    // Parse header using reader
    let mut r = reader::new(raw_block_header);

    // Parse fields in order
    let version = r.read_u32();           // 4 bytes
    let parent = r.read(32);              // 32 bytes
    let merkle_root = r.read(32);         // 32 bytes
    let hash_reserved = r.read(32);       // 32 bytes (Zcash-specific)
    let timestamp = r.read_u32();         // 4 bytes
    let bits = r.read_u32();              // 4 bytes
    let nonce = r.read(32);               // 32 bytes (NOT u32 like Bitcoin)

    // Compute block hash using SHA256d of the entire 140-byte header
    let block_hash = hash256(raw_block_header);

    BlockHeader {
        version,
        parent,
        merkle_root,
        hash_reserved,
        timestamp,
        bits,
        nonce,
        solution: vector::empty(),  // Solution not included in header parsing
        block_hash,
    }
}

public fun block_hash(header: &BlockHeader): vector<u8> {
    header.block_hash
}

public fun version(header: &BlockHeader): u32 {
    header.version
}

/// return parent block ID (hash)
public fun parent(header: &BlockHeader): vector<u8> {
    header.parent
}

public fun merkle_root(header: &BlockHeader): vector<u8> {
    header.merkle_root
}

public fun hash_reserved(header: &BlockHeader): vector<u8> {
    header.hash_reserved
}

public fun timestamp(header: &BlockHeader): u32 {
    header.timestamp
}

public fun bits(header: &BlockHeader): u32 {
    header.bits
}

public fun nonce(header: &BlockHeader): vector<u8> {
    header.nonce
}

public fun solution(header: &BlockHeader): vector<u8> {
    header.solution
}
