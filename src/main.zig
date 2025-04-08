const std = @import("std");
const clap = @import("clap");

const default_max_ticks: u32 = 40_000_000;

const Simulator = struct {
    max_ticks: u32,
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64, max_ticks: u32) Simulator {
        // TigerBeetle uses their own implementation for PRNG
        // For time purposes, we use the stdlib
        // Ref: https://github.com/tigerbeetle/tigerbeetle/blob/78ed407ba07ae674e8feda52dadddba234f4b7f7/src/stdx/prng.zig#L9
        return Simulator{
            .prng = std.Random.DefaultPrng.init(seed),
            .max_ticks = max_ticks,
        };
    }

    pub fn random_u64(self: *Simulator) u64 {
        return self.prng.random().int(u64);
    }
};

const Event = struct {
    timestamp: u64,
    callback: []const u8,

    pub fn format(self: Event, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Event: (timestamp = {d}, callback = {s})\n", .{ self.timestamp, self.callback });
    }
};

pub fn main() !void {

    // To parse CLI args
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // These are all the CLI args for now
    // TODO add config file
    // TODO take params outside of config file
    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\-s, --seed <u64>      An option parameter, takes a seed
        \\-t, --ticks <u32>     An option parameter, takes max ticks
    );

    // CLI parse
    // If any argument doesn't fit the above, return the help command
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = gpa.allocator(),
    }) catch {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    };
    defer res.deinit();

    // Display help if "-h, --help is called"
    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    // Set seed if seed not in args
    const seed_random = std.crypto.random.int(u64);
    const seed = if (res.args.seed) |s| s else seed_random;

    // Set max_ticks is ticks not in args
    const max_ticks = if (res.args.ticks) |t| t else default_max_ticks;

    // Initialize simulator
    var sim = Simulator.init(seed, max_ticks);

    std.debug.print("seed: {}\n", .{seed});
    std.debug.print("max_ticks: {}\n", .{max_ticks});

    const rand_int = sim.random_u64();
    std.debug.print("rand int: {}\n", .{rand_int});

    const heap_alloc = std.heap.page_allocator;

    const e1 = Event{ .timestamp = 0, .callback = "hello" };
    const e2 = Event{ .timestamp = 2, .callback = "world" };

    var event_queue = std.ArrayList(Event).init(heap_alloc);
    defer event_queue.deinit();
    try event_queue.append(e1);
    try event_queue.append(e2);

    for (event_queue.items) |event| {
        std.debug.print("{any}", .{event});
    }
}
