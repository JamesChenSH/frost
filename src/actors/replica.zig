const std = @import("std");
const fs = std.fs;
const log = std.log.scoped(.replica);

const Network = @import("../network.zig").Network;
const db_adapter = @import("../db/adapter.zig");
const messages = @import("../messages.zig");
const PRNG = @import("../prng.zig").PRNG;

pub const ReplicaActor = struct {
    id: u32,
    state: enum { Running, Paused, Crashed } = .Running,
    allocator: std.mem.Allocator,
    network: *Network,
    db: ?db_adapter.DbInterfaces = null, // Use DbInterfaces now
    db_path: []const u8, // Path is owned by Simulator

    pub fn init(
        allocator: std.mem.Allocator,
        id: u32,
        network: *Network,
        db_type: db_adapter.DbType,
        db_path_arg: []const u8,
    ) !ReplicaActor {
        log.info("Initializing Replica {} with DB path: {s}", .{ id, db_path_arg });

        // Ensure DB directory exists
        try fs.cwd().makePath(allocator, db_path_arg);

        const config = db_adapter.DbConfig{ .path = db_path_arg };
        // Initialize using DbInterfaces
        const adapter = try db_adapter.DbInterfaces.init(allocator, db_type, config);

        return ReplicaActor{
            .allocator = allocator,
            .id = id,
            .network = network,
            .db = adapter,
            .db_path = db_path_arg,
        };
    }

    pub fn deinit(self: *ReplicaActor) void {
        log.info("Deinitializing Replica {}", .{self.id});
        if (self.db) |*db_interface| {
            db_interface.deinit(); // Call deinit on DbInterfaces
            self.db = null;
        }
    }

    pub fn handleMessage(self: *ReplicaActor, message: messages.SimMessage, current_tick: u32) !void {
        if (self.state != .Running) {
            log.debug("Replica {} received message while {} state, ignoring.", .{ self.id, self.state });
            // IMPORTANT: If a GetResponse is ignored here, its payload needs freeing.
            // This is handled by scheduler's deinitEventPayload currently.
            return;
        }
        const db_interface = self.db orelse {
            log.err("Replica {} DB not initialized!", .{self.id});
            // Optionally send error response
            return;
        };

        log.debug("Replica {} handling message type {any} from {}", .{ self.id, message.payload, message.source_id });

        switch (message.payload) {
            .Request => |req_payload| {
                var response_payload: messages.ResponsePayload = undefined;
                const client_id = switch (req_payload) {
                    .Put => |p| p.client_id,
                    .Get => |g| g.client_id,
                };

                switch (req_payload) {
                    .Put => |put_req| {
                        log.debug("Replica {} processing PUT key='{s}'", .{ self.id, put_req.key });
                        const put_result = db_interface.put(put_req.key, put_req.value);
                        response_payload = .{ .Put = .{
                            .status = if (put_result) |_| messages.ResponseStatus.Ok else |err| blk: {
                                log.err("Replica {} PUT failed: {}", .{ self.id, err });
                                break :blk messages.ResponseStatus.Error;
                            },
                        } };
                    },
                    .Get => |get_req| {
                        log.debug("Replica {} processing GET key='{s}'", .{ self.id, get_req.key });
                        // Use replica's allocator for the potential result value
                        const get_result = db_interface.get(get_req.key, self.allocator);

                        if (get_result) |maybe_value| {
                            response_payload = .{ .Get = .{ .status = .Ok, .value = maybe_value } };
                        } else |err| {
                            log.warn("Replica {} GET failed: {}", .{ self.id, err });
                            const status = if (err == db_adapter.DbError.NotFound or err == db_adapter.DbError.BackendError) // Treat backend error as not found for simplicity now
                                messages.ResponseStatus.NotFound
                            else
                                messages.ResponseStatus.Error;
                            response_payload = .{ .Get = .{ .status = status, .value = null } };
                        }
                    },
                }

                // Send response back to client
                const response_message = messages.SimMessage{
                    .source_id = self.id,
                    .target_id = client_id,
                    .payload = response_payload,
                };
                // Pass current_tick for network latency calculation
                try self.network.sendMessage(self.id, client_id, response_message, current_tick);
            },
            .Response => {
                log.warn("Replica {} received unexpected Response message", .{self.id});
            },
        }
    }

    // Step is likely not needed unless replica has background tasks independent of messages
    pub fn step(self: *ReplicaActor, sim_prng: *PRNG) !void {
        if (self.state != .Running) return;
        _ = sim_prng;
    }

    pub fn pauseReplica(self: *ReplicaActor) void {
        if (self.state == .Running) {
            self.state = .Paused;
        }
    }

    pub fn resumeReplica(self: *ReplicaActor) void {
        if (self.state == .Paused) {
            self.state = .Running;
        }
    }
};
