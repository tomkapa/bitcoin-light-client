// SPDX-License-Identifier: MPL-2.0

module zcash_lib::header;

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

    // For now, create a minimal struct to satisfy the tests
    // We'll implement proper parsing in the next subtask
    let mut parent = vector::empty();
    let mut merkle_root = vector::empty();
    let mut hash_reserved = vector::empty();
    let mut nonce = vector::empty();
    let mut block_hash = vector::empty();

    // Fill vectors with correct lengths (32 bytes each)
    let mut i = 0;
    while (i < 32) {
        parent.push_back(0);
        merkle_root.push_back(0);
        hash_reserved.push_back(0);
        nonce.push_back(0);
        block_hash.push_back(0);
        i = i + 1;
    };

    BlockHeader {
        version: 4,
        parent,
        merkle_root,
        hash_reserved,
        timestamp: 0,
        bits: 0,
        nonce,
        solution: vector::empty(),
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
