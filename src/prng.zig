const std = @import("std");

/// This just re-exports DefaultPrng, but should be easier to find
/// If we want to implement our own, we can reuse this file
pub const PRNG = std.Random.DefaultPrng;

// You could add helper functions here if needed, e.g.,
// pub fn forkPrng(parent_prng: *PRNG, child_seed_entropy: u64) PRNG {
//     return PRNG.init(parent_prng.random().int(u64) ^ child_seed_entropy);
// }
