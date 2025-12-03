<!-- 89663968-a3ff-4d86-bafb-e9b87885e73a 0676970a-ac41-4efe-9450-2a7ce91876f5 -->
# Zcash Light Client Implementation Plan

## Key Differences: Bitcoin vs Zcash

| Component | Bitcoin | Zcash |

|-----------|---------|-------|

| Block Header | 80 bytes | ~1487 bytes (includes 1344-byte Equihash solution) |

| PoW Algorithm | SHA256d | Equihash (200,9 mainnet, 144,5 testnet) |

| Block Time | 10 min | 75 sec |

| Difficulty Adjustment | Every 2016 blocks | Every block (DigiShield variant) |

| Transaction Version | v1/v2 (SegWit) | v4 (transparent) |

| Address Prefix | t1/t3 vs 1/3 | Different prefixes |

## Architecture Decision: Direct On-Chain Equihash Verification

**Good news: Sui natively supports BLAKE2b-256** via `sui::hash::blake2b256`!

Equihash verification (not solving) is feasible in Move:

- **Solving** requires 2GB+ RAM (memory-hard) - done by miners
- **Verifying** only requires hash computations - can be done on-chain

Equihash (n, k) verification steps:

1. Parse solution indices from the solution bytes
2. For each index, compute BLAKE2b hash of (header || index)
3. Verify XOR collision tree (pairs XOR to values with leading zeros)
4. Verify indices are in sorted order
5. Check final result meets difficulty target

**Testnet uses Equihash (144,5)** - smaller/faster than mainnet (200,9):

- 32 indices (2^5) vs 512 indices (2^9)
- Much lower gas cost for verification

## Package Renaming

- `bitcoin_lib/` → `zcash_lib/`
- `bitcoin_spv/` → `zcash_spv/`
- `bitcoin_executor/` → (optional, lower priority)
- `nBTC/` → `nZEC/`

## Implementation Changes

### 1. zcash_lib/header.move - Block Header Structure

```move
// Zcash block header
public struct BlockHeader has copy, drop, store {
    version: u32,              // 4 bytes
    parent: vector<u8>,        // 32 bytes
    merkle_root: vector<u8>,   // 32 bytes  
    hash_reserved: vector<u8>, // 32 bytes (Zcash-specific)
    timestamp: u32,            // 4 bytes
    bits: u32,                 // 4 bytes
    nonce: vector<u8>,         // 32 bytes (vs 4 bytes in Bitcoin)
    solution: vector<u8>,      // Variable: 1344 bytes (200,9) or 100 bytes (144,5)
    block_hash: vector<u8>,    // computed via SHA256d
}
```

### 2. zcash_lib/crypto.move - Hash Functions

```move
// Use Sui's native BLAKE2b
use sui::hash::blake2b256;

// Zcash block hash uses SHA256d (same as Bitcoin)
public fun hash256(data: vector<u8>): vector<u8> {
    sha2_256(sha2_256(data))
}

// Equihash uses BLAKE2b with personalization
public fun equihash_hash(n: u32, k: u32, header: vector<u8>, index: u32): vector<u8>;
```

### 3. zcash_spv/equihash.move - Equihash Verification (NEW)

```move
module zcash_spv::equihash;

use sui::hash::blake2b256;

// Verify Equihash solution for testnet (144,5)
public fun verify_equihash_144_5(
    header_bytes: vector<u8>,  // 140 bytes without solution
    solution: vector<u8>,      // 100 bytes
): bool {
    // 1. Parse 32 indices from solution
    // 2. Compute collision tree using BLAKE2b
    // 3. Verify XOR constraints
    // 4. Return true if valid
}
```

### 4. zcash_spv/params.move - Network Parameters

```move
public fun testnet(): Params {
    Params {
        power_limit: 0x0007ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
        power_limit_bits: 0x2007ffff,
        blocks_pre_retarget: 1,  // Every block (DigiShield)
        target_timespan: 75,     // 75 seconds block time
        equihash_n: 144,
        equihash_k: 5,
        difficulty_adjustment: DIFFICULTYADJUSTMENT_DIGISHIELD,
    }
}
```

### 5. zcash_lib/tx.move - Transaction Format (v4)

Key changes for v4 transparent-only:

- Remove SegWit marker/flag
- Add `expiry_height: u32`
- Add `version_group_id: u32`
- Transaction hash uses BLAKE2b-256 with personalization "ZcashTxHash"

### 6. zcash_spv/light_client.move - Difficulty Adjustment

Replace Bitcoin's 2016-block retarget with DigiShield:

```move
public fun calc_next_required_difficulty(lc: &LightClient, parent: &LightBlock): u32 {
    // DigiShield algorithm:
    // averaging_window = 17 blocks
    // median_timespan = median of last 11 timestamps
    // Adjust target based on actual vs expected time
}
```

## Files to Modify/Create

| File | Action | Priority |

|------|--------|----------|

| `zcash_lib/sources/header.move` | Modify (new structure with solution) | High |

| `zcash_lib/sources/crypto.move` | Modify (use sui::hash::blake2b256) | High |

| `zcash_spv/sources/equihash.move` | Create (verification logic) | High |

| `zcash_spv/sources/params.move` | Modify (testnet params, DigiShield) | High |

| `zcash_lib/sources/tx.move` | Modify (v4 format) | High |

| `zcash_spv/sources/light_client.move` | Modify (DigiShield, Equihash check) | High |

| `zcash_spv/sources/header.move` | Modify (use Equihash instead of SHA256d PoW) | High |

| `zcash_lib/sources/output.move` | Minor (same P2PKH/P2SH) | Low |

| `nZEC/` | Rename and adapt | Medium |

## Testing Strategy

1. Use Zcash testnet block data (Equihash 144,5)
2. Create test vectors from real testnet blocks
3. Unit test Equihash verification with known solutions
4. Integration test with actual Zcash testnet RPC

### To-dos

- [ ] Rename bitcoin_lib to zcash_lib, bitcoin_spv to zcash_spv, nBTC to nZEC
- [ ] Update BlockHeader struct for Zcash (140 bytes, 32-byte nonce, hash_reserved)
- [ ] Implement Zcash testnet params (DigiShield, 75s blocks, new limits)
- [ ] Create committee.move for Equihash attestation verification
- [ ] Replace Bitcoin retarget with DigiShield per-block adjustment
- [ ] Update Transaction struct for v4 format (nExpiryHeight, versionGroupId)
- [ ] Decide BLAKE2b strategy: implement in Move or use committee attestation
- [ ] Update light_client.move to use committee verification instead of PoW check
- [ ] Create test vectors from Zcash testnet blocks