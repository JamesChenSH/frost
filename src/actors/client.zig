const std = @import("std");

const Network = @import("../network.zig").Network;
const PRNG = @import("../prng.zig").PRNG;
const Simulator = @import("../simulator.zig").Simulator; // Forward declare
const Adaptor = @import("../db/adapter.zig");

pub const ClientActor = struct {
    id: u32,
    // TODO: Add workload generator state
    allocator: std.mem.Allocator,
    network: *Network,
    prng: *PRNG, // For choosing operations/keys
    adaptor: *Adaptor.DbAdapter, // For database operations

    pub fn init(allocator: std.mem.Allocator, id: u32, network: *Network, prng: *PRNG) ClientActor {
        std.log.info("Initializing Client {}", .{id});
        return ClientActor{
            .allocator = allocator,
            .id = id,
            .network = network,
            .prng = prng,
            .adaptor = Adaptor.DbAdapter.init(allocator, Adaptor.DbType.RocksDB, Adaptor.DbConfig{
                .path = "../../tmp/db", // Placeholder path, create a database at project dir
            }) catch |err| {
                std.log.err("Failed to initialize DbAdapter for Client {}: {}", .{ id, err });
            },
        };
    }

    pub fn deinit(self: *ClientActor) void {
        std.log.info("Deinitializing Client {}", .{self.id});
    }

    pub fn handleMessage(self: *ClientActor, message: anytype) !void {
        // TODO: Process DB response (e.g., record result for verification)
        std.log.debug("Client {} handling message (placeholder)", .{self.id});
        // _ = self;
        _ = message;
    }

    // Pass simulator/scheduler time if needed for logging/logic
    pub fn step(self: *ClientActor, current_tick: u32) !void {
        // TODO: Implement workload generation logic
        // Decide operation (put/get/tx_begin/etc.) using self.prng
        // Choose target replica(s) using self.prng (or fixed logic)
        // Send request via self.network.sendMessage(...)
        // Record operation invocation for history/verification
        // _ = current_tick;

        if (self.prng.random().float(f32) < 0.1) { // Example: 10% chance to do something per step
            const target_replica_id = self.prng.random().uintLessThan(u32, 3); // Choose replica 0, 1, or 2
            std.log.debug("Client {} performing action targeting replica {} @ tick {} (placeholder)", .{ self.id, target_replica_id, current_tick });
            // Example: Send a dummy message to a replica
            // Actor IDs need careful management. Assume replica IDs are 0..N-1
            try self.network.sendMessage(self.id, target_replica_id, .{ .op = "dummy" });
        }
    }
};
