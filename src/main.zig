const std = @import("std");

const Simulator = struct {
    max_ticks: u32 = 40_000_000,
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Simulator {
        // TigerBeetle uses their own implementation for PRNG
        // For time purposes, we use the stdlib
        // Ref: https://github.com/tigerbeetle/tigerbeetle/blob/78ed407ba07ae674e8feda52dadddba234f4b7f7/src/stdx/prng.zig#L9
        const prng = std.Random.DefaultPrng.init(seed);
        return Simulator{
            .prng = prng,
        };
    }

    pub fn random_u64(self: Simulator) u64 {
        // NOTE: don't know why you have to copy a const into a var.
        // FIX this
        var prng = self.prng;
        const rand = prng.random();
        return rand.int(u64);
    }
};

pub fn main() !void {
    // TODO provide random seed or seed from argument
    const seed_random = std.crypto.random.int(u64);

    const sim = Simulator.init(seed_random);
    // It also works when seed is provided by user!
    // TODO allow CLI args to accept user provided seed
    // const sim = Simulator.init(0);

    const rand_int = sim.random_u64();
    std.debug.print("{}\n", .{rand_int});
}
