const std = @import("std");
const log = std.log.scoped(.network);

const Scheduler = @import("scheduler.zig").Scheduler;
const SimEventPayload = @import("scheduler.zig").SimEventPayload;
const PRNG = @import("prng.zig").PRNG;
const messages = @import("messages.zig");

pub const Network = struct {
    allocator: std.mem.Allocator,
    scheduler: *Scheduler,
    prng: PRNG, // Store struct directly
    // TODO: Add partition state, latency config from SimConfig

    pub fn init(allocator: std.mem.Allocator, scheduler: *Scheduler, prng_seed: u64) Network {
        return Network{
            .allocator = allocator,
            .scheduler = scheduler,
            .prng = PRNG.init(prng_seed),
        };
    }

    pub fn deinit(self: *Network) void {
        _ = self; // Nothing allocated directly by network currently
    }

    // Takes a full SimMessage now
    pub fn sendMessage(self: *Network, from_actor: u32, to_actor: u32, message: messages.SimMessage, current_tick: u32) !void {
        // Simulate latency deterministically
        // TODO: Read min/max latency from config
        const min_latency: u32 = 1;
        const max_latency: u32 = 5;
        const latency: u32 = min_latency + self.prng.random().uintLessThan(u32, max_latency - min_latency + 1);
        const delivery_tick = current_tick + latency;

        // TODO: Simulate drops/partitions using self.prng and config probabilities
        // if (self.prng.random().float(f32) < drop_probability) {
        //     log.warn("Network dropping message from {} to {} @ tick {}", .{from_actor, to_actor, current_tick});
        //     // Need to deallocate message payload if dropped!
        //     var dropped_msg = message; // Copy struct
        //     dropped_msg.deinitPayload(self.allocator); // Use network's allocator? Or simulator's? Pass allocator.
        //     return;
        // }

        // Create event payload containing the message
        const deliver_payload = SimEventPayload{
            .DeliverMessage = .{ .message = message },
        };

        // Schedule the delivery event
        try self.scheduler.scheduleEvent(delivery_tick, deliver_payload);

        log.debug("Network scheduled message type {any} from {} to {} @ tick {} (delivers @ {})", .{ message.payload, from_actor, to_actor, current_tick, delivery_tick });
    }
};
