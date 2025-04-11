const std = @import("std");
const Scheduler = @import("scheduler.zig").Scheduler;
const PRNG = @import("prng.zig").PRNG;

pub const Network = struct {
    allocator: std.mem.Allocator,
    scheduler: *Scheduler, // Network schedules message delivery events
    prng: *PRNG, // For latency/drop decisions

    // TODO: Add message queues
    // TODO: Add partition state

    pub fn init(allocator: std.mem.Allocator, scheduler: *Scheduler, prng: *PRNG) Network {
        return Network{
            .allocator = allocator,
            .scheduler = scheduler,
            .prng = prng,
        };
    }

    pub fn deinit(self: *Network) void {
        // TODO: Clean up message queues
        _ = self;
    }

    pub fn sendMessage(self: *Network, from_actor: u32, to_actor: u32, payload: anytype) !void {
        // TODO: Use PRNG and config to determine latency
        const latency: u32 = 1 + self.prng.random().uintLessThan(u32, 10); // Example
        const delivery_tick = self.scheduler.current_tick + latency; // Use scheduler's time

        // TODO: Use PRNG and config to check for drops/partitions

        // TODO: Create a 'DeliverMessage' event struct
        const deliver_event = .{ .to = to_actor, .payload = payload }; // Placeholder
        try self.scheduler.scheduleEvent(delivery_tick, deliver_event);

        std.log.debug("Network sending message from {} to {} @ tick {} (delivers @ {})", .{ from_actor, to_actor, self.scheduler.current_tick, delivery_tick });
        // TODO: Figure out what to do with payload
        // _ = payload; // Silence unused warning
    }
};
