// SPDX-License-Identifier: MPL-2.0

/// DigiShield v3 Difficulty Adjustment Algorithm for Zcash
///
/// This module implements the DigiShield v3 difficulty adjustment algorithm used by Zcash,
/// which provides per-block difficulty adjustments for more responsive mining difficulty.
///
/// # DigiShield v3 Mathematical Formula
///
/// The complete DigiShield v3 algorithm from zcash/src/pow.cpp:
///
/// ## Core Formula
/// ```
/// new_target = avg_target * clamped_timespan / target_timespan
/// ```
///
/// ## Parameters
/// - **averaging_window**: 17 blocks
///   The number of previous blocks used to calculate the average target.
///   Reference: nPowAveragingWindow in chainparams.cpp
///
/// - **target_spacing**: Block time in seconds
///   - Pre-Blossom (before block ~347500): 150 seconds
///   - Post-Blossom (after block ~347500): 75 seconds
///   Reference: PRE_BLOSSOM_POW_TARGET_SPACING and POST_BLOSSOM_POW_TARGET_SPACING
///
/// - **median_time_span**: 11 blocks
///   The number of blocks used to calculate median time past (MTP).
///   Reference: Standard Bitcoin/Zcash median time calculation
///
/// ## Damping Factor
/// To prevent oscillation and provide stability, DigiShield applies a damping factor of 4:
/// ```
/// damped_timespan = target_timespan + (actual_timespan - target_timespan) / 4
/// ```
/// This means only 25% of the deviation from target is applied each block.
///
/// ## Timespan Clamping
/// The damped timespan is clamped to prevent extreme adjustments:
/// ```
/// min_timespan = target_timespan * 3 / 4   // 75% of target (32% difficulty increase max)
/// max_timespan = target_timespan * 5 / 4   // 125% of target (16% difficulty decrease max)
/// ```
///
/// These bounds are derived from:
/// - nPowMaxAdjustUp = 16 (16% max difficulty decrease)
/// - nPowMaxAdjustDown = 32 (32% max difficulty increase)
/// - Clamping formula: averagingWindowTimespan * (100 + nPowMaxAdjustDown) / 100
///
/// ## Median Time Calculation
/// The timespan is calculated using Median Time Past (MTP) to prevent time-warp attacks:
/// ```
/// actual_timespan = MTP(block[N]) - MTP(block[N-27])
/// ```
///
/// Where:
/// - MTP(block[N]) = median of timestamps from blocks [N-10, N-9, ..., N]
/// - MTP(block[N-27]) = median of timestamps from blocks [N-37, N-36, ..., N-27]
/// - The span of 27 blocks comes from: averaging_window (17) + median_time_span (11) - 1
///
/// ## Complete Algorithm Steps
/// 1. Collect targets from last 17 blocks (heights N-16 to N)
/// 2. Calculate average target: avg_target = sum(targets) / 17
/// 3. Calculate MTP for current block (N) using 11-block median
/// 4. Calculate MTP for anchor block (N-27) using 11-block median
/// 5. Calculate actual_timespan = MTP(N) - MTP(N-27)
/// 6. Calculate target_timespan = target_spacing * averaging_window (e.g., 75 * 17 = 1275s)
/// 7. Apply damping: damped_timespan = target_timespan + (actual_timespan - target_timespan) / 4
/// 8. Clamp timespan: clamped_timespan = clamp(damped_timespan, min_timespan, max_timespan)
/// 9. Calculate new target: new_target = avg_target * clamped_timespan / target_timespan
/// 10. Ensure new_target <= power_limit
/// 11. Convert target to compact bits representation
///
/// ## References
/// - Zcash pow.cpp: https://github.com/zcash/zcash/blob/master/src/pow.cpp
/// - Zcash chainparams.cpp: https://github.com/zcash/zcash/blob/master/src/chainparams.cpp
/// - ZIP 208 (Blossom): https://zips.z.cash/zip-0208
/// - Zcash Protocol Specification: https://zips.z.cash/protocol/protocol.pdf
module zcash_spv::difficulty;

/// Error code: Invalid window size (must be exactly 17 for averaging window)
const E_INVALID_WINDOW_SIZE: u64 = 2;

/// Error code: Invalid timestamp count (must be exactly 11 for median calculation)
const E_INVALID_TIMESTAMP_COUNT: u64 = 3;

/// Error code: Invalid timestamp ordering (median_time_past must be >= median_time_first)
const E_INVALID_TIMESTAMP: u64 = 4;

/// Error code: avg_target exceeds power_limit
const E_TARGET_EXCEEDS_LIMIT: u64 = 5;

/// Calculate the next difficulty using DigiShield v3 algorithm
///
/// # Arguments
/// * `params` - Network parameters (testnet/mainnet)
/// * `avg_target` - Average target over the 17-block window
/// * `median_time_past` - MTP at current block (N)
/// * `median_time_first` - MTP at anchor block (N-27)
///
/// # Returns
/// The next difficulty target in compact bits format
public fun calc_next_difficulty(
    params: &zcash_spv::params::Params,
    avg_target: u256,
    median_time_past: u64,
    median_time_first: u64,
): u32 {
    use zcash_spv::params;

    // Validate avg_target doesn't exceed power_limit (defense against malformed input)
    let power_limit = params::power_limit(params);
    assert!(avg_target <= power_limit, E_TARGET_EXCEEDS_LIMIT);

    // Validate timestamps are in correct order
    assert!(median_time_past >= median_time_first, E_INVALID_TIMESTAMP);

    // Step 1: Calculate actual timespan
    let actual_timespan = (median_time_past - median_time_first) as u256;

    // Step 2: Calculate target timespan = target_spacing * averaging_window
    let target_spacing = params::target_spacing(params);
    let averaging_window = params::averaging_window(params);
    let target_timespan = (target_spacing * averaging_window) as u256;

    // Step 3: Apply damping factor of 4
    // damped_timespan = target_timespan + (actual_timespan - target_timespan) / 4
    let damped_timespan = if (actual_timespan >= target_timespan) {
        let diff = actual_timespan - target_timespan;
        target_timespan + (diff / 4)
    } else {
        let diff = target_timespan - actual_timespan;
        target_timespan - (diff / 4)
    };

    // Step 4: Apply clamping bounds (75% to 125%)
    let min_timespan = (target_timespan * 3) / 4;  // 75%
    let max_timespan = (target_timespan * 5) / 4;  // 125%

    let clamped_timespan = if (damped_timespan < min_timespan) {
        min_timespan
    } else if (damped_timespan > max_timespan) {
        max_timespan
    } else {
        damped_timespan
    };

    // Step 5: Calculate new target
    // Reorder operations to prevent integer overflow:
    // Instead of (avg_target * clamped_timespan) / target_timespan which could overflow
    // when avg_target is near power_limit and clamped_timespan is at max (125%),
    // we handle increase and decrease separately to avoid overflow
    let new_target = if (clamped_timespan >= target_timespan) {
        // Difficulty decreasing (target increasing)
        // Clamped at 125% max, so ratio is at most 1 (with remainder up to ~318)
        let ratio = clamped_timespan / target_timespan;
        let remainder = clamped_timespan % target_timespan;
        // Avoid overflow by dividing first, then multiplying:
        // avg_target * remainder could overflow (2^251 * 318 ≈ 2^259 > 2^256)
        // Instead: (avg_target / target_timespan) * remainder is safe (2^241 * 318 ≈ 2^249)
        // Plus: ((avg_target % target_timespan) * remainder) / target_timespan handles precision loss
        let quotient = avg_target / target_timespan;
        let modulo = avg_target % target_timespan;
        avg_target * ratio + quotient * remainder + (modulo * remainder) / target_timespan
    } else {
        // Difficulty increasing (target decreasing)
        // This path is safe from overflow as we're multiplying by a value < 1
        (avg_target * clamped_timespan) / target_timespan
    };

    // Step 6: Ensure new_target doesn't exceed power_limit
    let final_target = if (new_target > power_limit) {
        power_limit
    } else {
        new_target
    };

    // Step 7: Convert to compact bits format
    target_to_bits(final_target)
}

/// Calculate the average target over the 17-block averaging window
///
/// # Arguments
/// * `targets` - Vector of exactly 17 target values (u256 format)
///
/// # Returns
/// The average target
public fun calculate_average_target(targets: &vector<u256>): u256 {
    use std::vector;

    // Validate window size
    assert!(vector::length(targets) == 17, E_INVALID_WINDOW_SIZE);

    // Calculate sum of all targets
    // Safe from overflow: max sum = 17 * power_limit < 2^256
    // Even at maximum difficulty (power_limit), 17 targets sum to less than u256::MAX
    let mut sum: u256 = 0;
    let mut i = 0;
    while (i < 17) {
        sum = sum + *vector::borrow(targets, i);
        i = i + 1;
    };

    // Return average
    sum / 17
}

/// Calculate the median timestamp from an 11-block window
///
/// # Arguments
/// * `timestamps` - Vector of exactly 11 timestamps
///
/// # Returns
/// The median timestamp (6th element after sorting)
public fun calc_median_timestamp(timestamps: &vector<u64>): u64 {
    use std::vector;

    // Validate timestamp count
    assert!(vector::length(timestamps) == 11, E_INVALID_TIMESTAMP_COUNT);

    // Copy the vector to sort it (we can't modify the input)
    let mut sorted = vector::empty<u64>();
    let mut i = 0;
    while (i < 11) {
        vector::push_back(&mut sorted, *vector::borrow(timestamps, i));
        i = i + 1;
    };

    // Simple bubble sort with explicit types for safety
    // O(n²) complexity is acceptable for n=11; more complex algorithms
    // would add unnecessary code complexity and gas costs for minimal gain
    let mut n: u64 = 11;
    while (n > 1) {
        let mut i: u64 = 0;
        while (i < n - 1) {
            let a = *vector::borrow(&sorted, i);
            let b = *vector::borrow(&sorted, i + 1);
            if (a > b) {
                *vector::borrow_mut(&mut sorted, i) = b;
                *vector::borrow_mut(&mut sorted, i + 1) = a;
            };
            i = i + 1;
        };
        n = n - 1;
    };

    // Return the median (6th element, index 5)
    *vector::borrow(&sorted, 5)
}

/// Convert a u256 target to compact bits representation
///
/// # Arguments
/// * `target` - The target in u256 format
///
/// # Returns
/// The target in compact bits format (u32)
///
/// # Algorithm
/// Compact bits format: exponent (1 byte) + mantissa (3 bytes)
/// target = mantissa × 256^(exponent - 3)
public fun target_to_bits(target: u256): u32 {
    if (target == 0) {
        return 0
    };

    // Find the most significant byte position
    // We count bytes from right to left (LSB to MSB)
    let mut size = 0;
    let mut temp = target;

    // Count the number of bytes needed to represent the target
    while (temp > 0) {
        temp = temp >> 8;
        size = size + 1;
    };

    // Extract the mantissa (top 3 bytes)
    let mut mantissa = if (size <= 3) {
        (target << (8 * (3 - size))) as u32
    } else {
        (target >> (8 * (size - 3))) as u32
    };

    // Handle negative bit (if high bit is set, need to shift)
    if (mantissa & 0x00800000 != 0) {
        mantissa = mantissa >> 8;
        size = size + 1;
    };

    // Combine size (exponent) and mantissa
    ((size as u32) << 24) | (mantissa & 0x00ffffff)
}

/// Convert compact bits to u256 target
///
/// # Arguments
/// * `bits` - The target in compact bits format
///
/// # Returns
/// The target in u256 format
///
/// # Algorithm
/// Compact bits format: exponent (1 byte) + mantissa (3 bytes)
/// target = mantissa × 256^(exponent - 3)
///
/// # Note
/// This is a pure conversion function. Callers should validate the resulting
/// target against power_limit if needed (e.g., when validating block headers).
public fun bits_to_target(bits: u32): u256 {
    // Extract size (exponent) and mantissa
    let size = (bits >> 24) & 0xff;
    let mantissa = bits & 0x00ffffff;

    // Validate sign bit is not set (negative targets are invalid)
    // If the high bit of mantissa is set, this represents a negative value
    assert!(mantissa & 0x00800000 == 0, E_INVALID_WINDOW_SIZE); // Reusing error code

    // Calculate target = mantissa * 256^(size - 3)
    let mut target = mantissa as u256;

    if (size <= 3) {
        // Shift right if size is 3 or less
        let shift_amount = ((3 - size) * 8) as u8;
        target = target >> shift_amount;
    } else {
        // Shift left if size is greater than 3
        let shift_amount = ((size - 3) * 8) as u8;
        target = target << shift_amount;
    };

    target
}
