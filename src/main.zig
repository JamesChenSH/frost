const std = @import("std");

const clap = @import("clap");

const config = @import("config.zig");
const Simulator = @import("simulator.zig").Simulator;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // CLI args using defaults from config.zig
    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-s, --seed <u64>        Simulation seed (default: random)
        \\-t, --ticks <u32>       Max simulation ticks
        \\-r, --replicas <u32>    Number of replicas
        \\-c, --clients <u32>     Number of clients
        \\    --pause_prob <f32>  Replica pause probability per tick
        \\    --resume_prob <f32> Replica resume probability per tick
    );

    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = allocator,
    }) catch |err| {
        std.log.err("Input Error: {}\n", .{err});
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    // --- Build Configuration ---
    // Use 'orelse' with defaults from config.zig
    const seed: u64 = res.args.seed orelse std.crypto.random.int(u64);
    const simulation_config = config.SimulationConfig{
        .seed = seed,
        .max_ticks = res.args.ticks orelse config.default_max_ticks,
        .num_replicas = res.args.replicas orelse config.default_num_replicas,
        .num_clients = res.args.clients orelse config.default_num_clients,
        .replica_pause_probability = res.args.pause_prob orelse config.default_replica_pause_probability,
        .replica_resume_probability = res.args.resume_prob orelse config.default_replica_resume_probability,
    };

    std.log.info("Initializing simulation with config: {any}", .{simulation_config});

    // --- Initialize and Run Simulator ---
    var sim = try Simulator.init(allocator, simulation_config);
    defer sim.deinit(); // Ensure cleanup

    try sim.run(); // Execute the main simulation loop

    std.log.info("Simulation completed successfully.", .{});
}
