const std = @import("std");
const PriorityQueue = std.PriorityQueue;
const log = std.log.scoped(.scheduler);
const math = std.math; // Import math for Order

const PRNG = @import("prng.zig").PRNG;
const messages = @import("messages.zig");
const ReplicaActor = @import("actors/replica.zig").ReplicaActor;
const ClientActor = @import("actors/client.zig").ClientActor;

// --- Event Definition ---
const DeliverMessage = struct {
    message: messages.SimMessage,
};

pub const SimEventPayload = union(enum) {
    DeliverMessage: DeliverMessage,
    // EndPause: struct { replica_id: u32 },
};

pub const SimEvent = struct {
    tick: u32,
    payload: SimEventPayload,

    pub fn lessThan(context: void, a: SimEvent, b: SimEvent) math.Order {
        _ = context;
        return math.order(a.tick, b.tick);
    }
};

// --- Scheduler ---
pub const Scheduler = struct {
    allocator: std.mem.Allocator,
    event_queue: PriorityQueue(SimEvent, void, SimEvent.lessThan),

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return Scheduler{
            .allocator = allocator,
            .event_queue = PriorityQueue(SimEvent, void, SimEvent.lessThan).init(allocator, {}),
        };
    }

    pub fn deinit(self: *Scheduler) void {
        log.info("Scheduler deinit: Clearing {d} remaining events.", .{self.event_queue.count()});

        // 1. removeOrNull() returns ?SimEvent
        // 2. while unwraps the optional. If non-null, assigns the SimEvent value
        //    to the *immutable* loop variable 'event_value'.
        while (self.event_queue.removeOrNull()) |event_value| {
            // 3. Create a *mutable* local copy from the immutable loop variable.
            var event_mutable_copy = event_value;

            // 4. Pass the address of the *mutable* copy to the function
            //    expecting a mutable pointer (*SimEvent).
            Scheduler.deinitEventPayload(&event_mutable_copy, self.allocator);
        }
        self.event_queue.deinit();
    }

    // deinitEventPayload expects *SimEvent (mutable pointer)
    pub fn deinitEventPayload(event_ptr: *SimEvent, allocator: std.mem.Allocator) void {
        log.debug("Deiniting payload for event @ tick {d}", .{event_ptr.tick});
        switch (event_ptr.payload) {
            .DeliverMessage => |*dm| { // dm is *DeliverMessage (mutable)
                dm.message.deinitPayload(allocator);
            },
            // .EndPause => {},
        }
    }

    pub fn scheduleEvent(self: *Scheduler, tick: u32, payload: SimEventPayload) !void {
        const event = SimEvent{ .tick = tick, .payload = payload };
        log.debug("event_queue_cap = {}", .{self.event_queue.capacity()});
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

        // Peek returns ?*const T
        while (self.event_queue.peek()) |event_ptr| {
            // event_ptr is *const SimEvent

            // Check if the event is for the current tick *before* making a copy
            if (event_ptr.tick > current_tick) {
                break; // Event is in the future
            }

            // Event is for the current tick. Remove it from the queue.
            // remove() returns the actual T value.
            var event = self.event_queue.remove();

            // Defer deinit using a pointer to the mutable copy we just removed.
            defer Scheduler.deinitEventPayload(&event, allocator);

            log.debug("Scheduler processing event for tick {}: {any}", .{ event.tick, event.payload });

            // Switch on the mutable copy's payload
            switch (event.payload) {
                // Capture immutable payload for message handling logic
                .DeliverMessage => |dm_const| {
                    // dm_const is const DeliverMessage here
                    const target_id = dm_const.message.target_id;
                    if (target_id < 1000) { // Replica
                        if (target_id < replicas.items.len) {
                            try replicas.items[target_id].handleMessage(dm_const.message, current_tick);
                        } else {
                            log.err("Scheduler: Invalid target replica ID {} in message from {}", .{ target_id, dm_const.message.source_id });
                        }
                    } else { // Client
                        const client_index = target_id - 1000;
                        if (client_index < clients.items.len) {
                            try clients.items[client_index].handleMessage(dm_const.message, current_tick);
                        } else {
                            log.err("Scheduler: Invalid target client ID {} in message from {}", .{ target_id, dm_const.message.source_id });
                        }
                    }
                },
                // Handle other event types here
            }
        }
    }
};
