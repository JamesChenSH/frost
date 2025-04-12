const std = @import("std");

const Network = @import("../network.zig").Network;
const Simulator = @import("../simulator.zig").Simulator;

pub const ReplicaActor = struct {
    id: u32,
    state: enum { Running, Paused, Crashed } = .Running,
    // TODO: Add reference to the actual DB instance (e.g., RocksDB handle via FFI)
    // TODO: Add internal state (e.g., pending transaction)
    allocator: std.mem.Allocator,
    network: *Network,

    pub fn init(allocator: std.mem.Allocator, id: u32, network: *Network) ReplicaActor {
        std.log.info("Initializing Replica {}", .{id});
        // TODO: Initialize the actual DB instance here (e.g., rocksdb_open)
        return ReplicaActor{
            .allocator = allocator,
            .id = id,
            .network = network,
        };
    }

    pub fn deinit(self: *ReplicaActor) void {
        std.log.info("Deinitializing Replica {}", .{self.id});
        // TODO: Clean up DB instance (e.g., rocksdb_close)
    }

    pub fn handleMessage(self: *ReplicaActor, message: anytype) !void {
        if (self.state != .Running) return; // Ignore if not running
        std.log.debug("Replica {} handling message (placeholder)", .{self.id});
        // TODO: Process DB request based on message
        // TODO: Call FFI functions for the target DB
        // TODO: Send response via self.network.sendMessage(...)
        _ = message;
    }

    // Pass simulator only if needed for context (like PRNG for internal random decisions)
    pub fn step(self: *ReplicaActor, sim_prng: *std.Random.DefaultPrng) !void {
        if (self.state != .Running) return;
        // TODO: Perform any background work? Periodic tasks?
        // This might not be needed if strictly event-driven
        // _ = self;
        _ = sim_prng; // silence unused
    }

    pub fn pauseReplica(self: *ReplicaActor) void {
        if (self.state == .Running) {
            std.log.warn("Pausing Replica {}", .{self.id});
            self.state = .Paused;
            // TODO: Schedule an 'EndPause' event? Or handle in scheduler?
        }
    }

    pub fn resumeReplica(self: *ReplicaActor) void {
        if (self.state == .Paused) {
            std.log.warn("Resuming Replica {}", .{self.id});
            self.state = .Running;
        }
    }

    // TODO: Not implemented yet
    // pub fn crashReplica(self: *ReplicaActor) void {
    //     if (self.state != .Crashed) {
    //         std.log.err("Crashing Replica {}", .{self.id});
    //         self.state = .Crashed;
    //         // TODO: Maybe release resources? Depends on crash model.
    //     }
    // }
};
