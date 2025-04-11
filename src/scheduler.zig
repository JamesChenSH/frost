const std = @import("std");
const Simulator = @import("simulator.zig").Simulator;

pub const Scheduler = struct {
    // TODO: Implement event queue (priority queue based on virtual time)
    // TODO: Manage runnable actors
    allocator: std.mem.Allocator,
    current_tick: u32 = 0, // Scheduler needs to know the time for scheduling

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return Scheduler{ .allocator = allocator };
    }

    pub fn deinit(self: *Scheduler) void {
        // TODO: Clean up any allocations (e.g., event queue nodes)
        _ = self; // Silence unused warning for now
    }

    pub fn scheduleEvent(self: *Scheduler, tick: u32, event: anytype) !void {
        // TODO: Add event to priority queue
        _ = self;
        // _ = tick;
        _ = event;
        std.log.debug("Scheduling event at tick {} (placeholder)", .{tick});
        return;
    }

    // Changed sim parameter type to avoid circular dependency issues initially.
    // Pass only needed parts or use interfaces later.
    pub fn runTick(self: *Scheduler, sim_prng: *std.Random.DefaultPrng) !void {
        // TODO: Process events scheduled for self.current_tick
        // TODO: Decide which actors run this tick (using sim_prng for determinism)
        // TODO: Return list of actors to run, or directly call their 'step' methods?
        // TODO: Potentially trigger faults via sim.injectFaults() (maybe move fault injection call?)

        if (self.current_tick % 100_000 == 0) { // Log progress occasionally
            std.log.debug("Scheduler running tick {}", .{self.current_tick});
        }
        _ = sim_prng; // silence unused
    }

    pub fn advanceTick(self: *Scheduler) void {
        self.current_tick += 1;
    }
};
