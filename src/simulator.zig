// src/simulator.zig
const std = @import("std");
const fs = std.fs;
const log = std.log.scoped(.simulator);

const config = @import("config.zig");
const PRNG = @import("prng.zig").PRNG;
const Scheduler = @import("scheduler.zig").Scheduler;
const Network = @import("network.zig").Network;
const ReplicaActor = @import("actors/replica.zig").ReplicaActor;
const ClientActor = @import("actors/client.zig").ClientActor;
const db_adapter = @import("db/adapter.zig");
const messages = @import("messages.zig");

// Base path for simulation database directories
const base_db_path = config.default_sim_db_data;

pub const Simulator = struct {
    simulation_config: config.SimulationConfig,
    prng: PRNG,
    allocator: std.mem.Allocator,

    // Core Components
    scheduler: Scheduler,
    network: Network,
    replicas: std.ArrayList(ReplicaActor),
    clients: std.ArrayList(ClientActor),

    // Paths for replica DBs (owned by simulator)
    replica_db_paths: std.ArrayList([]u8), // Store mutable slices

    // Client PRNGs
    client_prngs: std.ArrayList(PRNG),

    pub fn init(allocator: std.mem.Allocator, simulation_config: config.SimulationConfig) !Simulator {
        log.info("Simulator init start", .{});
        var simulator_prng = PRNG.init(simulation_config.seed);

        // Init Scheduler & Network
        var scheduler = Scheduler.init(allocator);
        var network = Network.init(allocator, &scheduler, simulator_prng.random().int(u64));

        // Initialize lists after
        var replicas = std.ArrayList(ReplicaActor).init(allocator);
        errdefer replicas.deinit();
        var clients = std.ArrayList(ClientActor).init(allocator);
        errdefer clients.deinit();
        var client_prngs_list = std.ArrayList(PRNG).init(allocator);
        errdefer client_prngs_list.deinit();
        var replica_db_paths_list = std.ArrayList([]u8).init(allocator); // Store mutable paths
        errdefer replica_db_paths_list.deinit();

        // --- Init Replicas ---
        log.info("Creating base DB directory: {s}", .{base_db_path});
        try fs.cwd().makePath(base_db_path);

        errdefer { // Cleanup partially created replicas and paths
            log.warn("Error during replica init, cleaning up...", .{});
            for (replicas.items) |*r| r.deinit();
            for (replica_db_paths_list.items) |p| allocator.free(p);
        }
        log.info("Initializing {d} replicas", .{simulation_config.num_replicas});
        for (0..simulation_config.num_replicas) |i| {
            const replica_id: u32 = @intCast(i);
            const path = try std.fmt.allocPrint(allocator, "{s}/replica_{d}", .{ base_db_path, replica_id });
            // Must handle path allocation failure before appending
            errdefer allocator.free(path);

            // Append path *before* potentially failing Replica init
            try replica_db_paths_list.append(path);

            log.debug("Attempting to init Replica {d} with path {s}", .{ replica_id, path });
            // Now that path is in the list, init the replica. If this fails, outer errdefer handles path cleanup.
            try replicas.append(try ReplicaActor.init(
                allocator,
                replica_id,
                &network,
                .RocksDB, // TODO: Use config value later
                path, // Pass the allocated path slice
            ));
            log.debug("Replica {d} initialized successfully", .{replica_id});
        }

        // --- Init Clients ---
        errdefer {
            log.warn("Error during client init, cleaning up...", .{});
            for (clients.items) |*c| c.deinit();
        }
        log.info("Initializing {d} clients", .{simulation_config.num_clients});
        for (0..simulation_config.num_clients) |i| {
            const client_id: u32 = @intCast(1000 + i);
            try clients.append(ClientActor.init(
                allocator,
                client_id,
                &network,
                simulator_prng.random().int(u64),
                simulation_config.num_replicas, // Pass replica count
                simulation_config.client_request_probability,
            ));
            log.debug("Client {d} initialized successfully", .{client_id});
        }

        log.info("Simulator init complete", .{});
        return Simulator{
            .simulation_config = simulation_config,
            .prng = simulator_prng,
            .allocator = allocator,
            .scheduler = scheduler,
            .network = network,
            .replicas = replicas,
            .clients = clients,
            .client_prngs = client_prngs_list,
            .replica_db_paths = replica_db_paths_list,
        };
    }

    pub fn deinit(self: *Simulator) void {
        log.info("Simulator deinit start", .{});
        // Deinit actors first, releasing DB handles
        for (self.clients.items) |*c| c.deinit();
        self.clients.deinit();
        for (self.replicas.items) |*r| r.deinit();
        self.replicas.deinit();

        // Free allocated replica path strings
        for (self.replica_db_paths.items) |p| self.allocator.free(p);
        self.replica_db_paths.deinit();

        // Deinit client PRNGs list
        self.client_prngs.deinit();

        // Deinit network and scheduler (scheduler deinit cleans event queue)
        self.network.deinit();
        self.scheduler.deinit();

        // Optional: Clean up database directory after everything is closed
        _ = fs.cwd().deleteTree(base_db_path) catch |err| {
            log.warn("Could not delete DB data directory '{s}': {}", .{ base_db_path, err });
        };
        log.info("Simulator deinit complete.", .{});
    }

    pub fn randomU64(self: *Simulator) u64 {
        return self.prng.random().int(u64);
    }

    pub fn randomF32(self: *Simulator) f32 {
        return self.prng.random().float(f32);
    }

    pub fn run(self: *Simulator) !void {
        log.info("Starting simulation run...", .{});
        var current_tick: u32 = 0;
        for (0..self.simulation_config.max_ticks) |curr_tick_usize| {
            current_tick = @intCast(curr_tick_usize);

            // 1. Update replica states (faults/resume)
            try self.updateReplicaStates(current_tick);

            // 2. Execute Client Steps (Generate workload -> sends messages)
            for (self.clients.items) |*client| {
                try client.step(current_tick);
            }

            // 3. Advance Scheduler & Process Events (incl. message delivery)
            // Pass allocator for freeing message payloads if needed
            try self.scheduler.runTick(self.allocator, &self.prng, current_tick, &self.clients, &self.replicas);

            // 4. Replica steps are now driven by messages handled in runTick

            if (current_tick > 0 and current_tick % 200_000 == 0) { // Log progress less often
                log.info("Tick {d} / {d}", .{ current_tick, self.simulation_config.max_ticks });
            }
        }
        // Final tick count might be max_ticks-1 because loop is 0..max_ticks
        log.info("Simulation finished after {d} ticks.", .{current_tick + 1});
    }

    fn updateReplicaStates(self: *Simulator, current_tick: u32) !void {
        // Iterate through replicas to update state
        for (self.replicas.items) |*replica| {
            const initial_state = replica.state;
            if (initial_state == .Crashed) continue;

            if (initial_state == .Running) {
                if (self.randomF32() < self.simulation_config.replica_pause_probability) {
                    log.warn("Injecting PAUSE fault for Replica {d} at tick {d}", .{ replica.id, current_tick });
                    replica.pauseReplica();
                    continue; // Don't try to resume in the same tick
                }
            } else if (initial_state == .Paused) {
                if (self.randomF32() < self.simulation_config.replica_resume_probability) {
                    log.warn("Injecting RESUME event for Replica {d} at tick {d}", .{ replica.id, current_tick });
                    replica.resumeReplica();
                }
            }
        }
    }
};
