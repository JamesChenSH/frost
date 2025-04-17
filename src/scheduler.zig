// src/scheduler.zig
const std = @import("std");
const PQueue = std.PriorityQueue;
const log = std.log.scoped(.scheduler);

const PRNG = @import("prng.zig").PRNG;
const messages = @import("messages.zig");
// Need full actor types for calling handleMessage
const ReplicaActor = @import("actors/replica.zig").ReplicaActor;
const ClientActor = @import("actors/client.zig").ClientActor;

// --- Event Definition ---
const DeliverMessage = struct {
    message: messages.SimMessage,
};

const SimEventPayload = union(enum) {
    DeliverMessage: DeliverMessage,
    // EndPause: struct { replica_id: u32 },
};

pub const SimEvent = struct {
    tick: u32, // Time the event should occur
    payload: SimEventPayload,

    pub fn lessThan(_: void, context: void, a: SimEvent, b: SimEvent) bool {
        _ = context;
        return a.tick < b.tick;
    }
};

// --- Scheduler ---
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    event_queue: PQueue(SimEvent, void, SimEvent.lessThan),

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return Scheduler{
            .allocator = allocator,
            .event_queue = PQueue(SimEvent, void, SimEvent.lessThan).init(allocator, {}),
        };
    }

    pub fn deinit(self: *Scheduler) void {
        log.info("Scheduler deinit: Clearing {} remaining events.", .{self.event_queue.len});
        while (self.event_queue.removeOrNull()) |event| {
            // Call the static helper method using Self
            Scheduler.deinitEventPayload(event, self.allocator);
        }
        self.event_queue.deinit();
    }

    // Helper to free potential allocations within an event payload
    // Made static (pub fn) as it doesn't depend on 'self' state
    pub fn deinitEventPayload(event: SimEvent, allocator: std.mem.Allocator) void {
        log.debug("Deiniting payload for event @ tick {}", .{event.tick});
        switch (event.payload) {
            .DeliverMessage => |*dm| {
                dm.message.deinitPayload(allocator);
            },
            // .EndPause => {},
        }
    }

    pub fn scheduleEvent(self: *Scheduler, tick: u32, payload: SimEventPayload) !void {
        const event = SimEvent{ .tick = tick, .payload = payload };
        try self.event_queue.add(event);
    }

    pub fn runTick(
        self: *Scheduler,
        allocator: std.mem.Allocator,
        sim_prng: *PRNG,
        current_tick: u32,
        clients: *std.ArrayList(ClientActor),
        replicas: *std.ArrayList(ReplicaActor),
    ) !void {
        _ = sim_prng;

        while (self.event_queue.peek()) |event| {
            if (event.tick > current_tick) {
                break;
            }

            const current_event = self.event_queue.remove();
            // Call the static helper using Self. This is now correct.
            defer Scheduler.deinitEventPayload(current_event, allocator);

            log.debug("Scheduler processing event for tick {}: {any}", .{ current_event.tick, current_event.payload });

            switch (current_event.payload) {
                .DeliverMessage => |dm| {
                    const target_id = dm.message.target_id;
                    if (target_id < 1000) { // Replica
                        if (target_id < replicas.items.len) {
                            try replicas.items[target_id].handleMessage(dm.message, current_tick);
                        } else {
                            log.err("Scheduler: Invalid target replica ID {} in message from {}", .{ target_id, dm.message.source_id });
                        }
                    } else { // Client
                        const client_index = target_id - 1000;
                        if (client_index < clients.items.len) {
                            try clients.items[client_index].handleMessage(dm.message, current_tick);
                        } else {
                            log.err("Scheduler: Invalid target client ID {} in message from {}", .{ target_id, dm.message.source_id });
                        }
                    }
                },
                // Handle other event types here
            }
        }
    }
};
