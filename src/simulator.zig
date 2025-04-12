const std = @import("std");

const config = @import("config.zig");
const PRNG = @import("prng.zig").PRNG;
const Scheduler = @import("scheduler.zig").Scheduler;
const Network = @import("network.zig").Network;
const ReplicaActor = @import("actors/replica.zig").ReplicaActor;
const ClientActor = @import("actors/client.zig").ClientActor;

pub const Simulator = struct {
    simulation_config: config.SimulationConfig,
    prng: PRNG, // Main PRNG for simulator-level decisions
    allocator: std.mem.Allocator,

    // Core Components
    scheduler: Scheduler,
    network: Network,
    replicas: std.ArrayList(ReplicaActor),
    clients: std.ArrayList(ClientActor),

    // Client PRNGs (Forked per client for determinism)
    // Store them here or within ClientActor depending on preference
    client_prngs: std.ArrayList(PRNG),

    // TODO: Add History Recorder
    // TODO: Add Checker/Verifier

    pub fn init(allocator: std.mem.Allocator, simulation_config: config.SimulationConfig) !Simulator {
        var simulator_prng = PRNG.init(simulation_config.seed);
        // Fork PRNGs deterministically *before* using the simulator_prng for anything else
        var network_prng = PRNG.init(simulator_prng.random().int(u64));
        var client_prng_master = PRNG.init(simulator_prng.random().int(u64));

        var scheduler = Scheduler.init(allocator);
        var network = Network.init(allocator, &scheduler, &network_prng);

        var replicas = std.ArrayList(ReplicaActor).init(allocator);
        errdefer replicas.deinit(); // Deinit already created replicas if client init fails below

        var clients = std.ArrayList(ClientActor).init(allocator);
        errdefer clients.deinit(); // Deinit client list if something below fails

        var client_prngs_list = std.ArrayList(PRNG).init(allocator);
        errdefer client_prngs_list.deinit(); // Deinit PRNG list if something below fails

        // Init Replicas
        for (0..simulation_config.num_replicas) |i| {
            // Pass network, etc.
            // Use @truncate since we know number of replicas cannot exceed u32_MAX, and usually be below 10
            // Since ReplicaActor expects a u32 and i is a usize
            try replicas.append(ReplicaActor.init(allocator, @truncate(i), &network));
        }

        // Init Clients and their PRNGs
        errdefer { // More complex cleanup if client init fails mid-loop
            for (clients.items) |*c| c.deinit();
            // No need to deinit client_prngs items, they are structs
        }
        for (0..simulation_config.num_clients) |i| {
            // Fork a PRNG for each client
            const client_prng = PRNG.init(client_prng_master.random().int(u64));
            try client_prngs_list.append(client_prng); // Store the PRNG
            // Client ID = 1000 + i for distinctness
            // Pass the corresponding PRNG by pointer
            // Same as above. use @truncate since we know number of replicas cannot exceed u32_MAX, and usually be below 10
            // Since ClientActor expects a u32 and i is a usize
            try clients.append(ClientActor.init(allocator, @truncate(1000 + i), &network, &client_prngs_list.items[i]));
        }

        return Simulator{
            .simulation_config = simulation_config,
            .prng = simulator_prng,
            .allocator = allocator,
            .scheduler = scheduler,
            .network = network,
            .replicas = replicas,
            .clients = clients,
            .client_prngs = client_prngs_list, // Own the list
        };
    }

    pub fn deinit(self: *Simulator) void {
        std.log.info("Deinitializing simulation", .{});
        for (self.clients.items) |*c| c.deinit();
        self.clients.deinit();

        // No need to deinit client_prngs items, just the list
        self.client_prngs.deinit();

        for (self.replicas.items) |*r| r.deinit();
        self.replicas.deinit();

        self.network.deinit();
        self.scheduler.deinit(); // Deinit scheduler last
    }

    pub fn randomU64(self: *Simulator) u64 {
        return self.prng.random().int(u64);
    }

    pub fn randomF32(self: *Simulator) f32 {
        return self.prng.random().float(f32);
    }

    pub fn run(self: *Simulator) !void {
        std.log.info("Starting simulation run...", .{});
        while (self.scheduler.current_tick < self.simulation_config.max_ticks) {
            const current_tick = self.scheduler.current_tick;

            // 1. Inject Faults (Probabilistic)
            try self.injectFaults(current_tick);

            // 2. Advance Scheduler & Process Events
            try self.scheduler.runTick(&self.prng);
            // TODO: The scheduler should ideally tell the simulator which actors need stepping
            // based on events (e.g., message delivery, timer expiry).

            // 3. Execute Actor Steps (Placeholder - should be driven by scheduler)
            // For now, give each actor a chance to run each tick deterministically
            // Shuffling actor execution order might be needed for more complex scenarios.
            // A simple approach: run clients then replicas. Deterministic order.
            for (self.clients.items) |*client| {
                // Pass current tick for context/logging
                try client.step(current_tick);
            }
            for (self.replicas.items) |*replica| {
                // Pass main PRNG for now if replica needs random decisions during its step
                try replica.step(&self.prng);
            }

            // 4. Advance Time (handled by scheduler now)
            self.scheduler.advanceTick();

            if (current_tick % 500_000 == 0 and current_tick > 0) { // Log progress
                std.log.info("Tick {} / {}", .{ current_tick, self.simulation_config.max_ticks });
            }
        }
        std.log.info("Simulation finished after {} ticks.", .{self.scheduler.current_tick});

        // TODO: Run Verifier/Checker on recorded history
    }

    fn injectFaults(self: *Simulator, current_tick: u32) !void {
        // Inject Replica Faults
        for (self.replicas.items) |*replica| {
            if (replica.state == .Crashed) continue; // Don't inject into crashed replicas

            // TODO: Not implemented
            // Check Crash
            // if (self.randomF32() < self.config.replica_crash_probability) {
            //     std.log.warn("Injecting CRASH fault for Replica {} at tick {}", .{ replica.id, current_tick });
            //     replica.crash();
            //     continue; // Don't pause a replica that just crashed
            // }

            // Check Pause (only if running)
            if (replica.state == .Running and self.randomF32() < self.simulation_config.replica_pause_probability) {
                std.log.warn("Injecting PAUSE fault for Replica {} at tick {}", .{ replica.id, current_tick });
                replica.pauseReplica();
                // TODO: Schedule an EndPause event using the scheduler
                // const pause_duration = 100 + @intCast(self.randomU64() % 900); // Example
                // try self.scheduler.scheduleEvent(current_tick + pause_duration, .{ .resume_replica = replica.id });
            }
        }

        // TODO: Inject Network Faults (Partitions, High Latency)
    }
};
