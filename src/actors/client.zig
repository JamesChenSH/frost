const std = @import("std");
const log = std.log.scoped(.client);

const Network = @import("../network.zig").Network;
const PRNG = @import("../prng.zig").PRNG;
const messages = @import("../messages.zig");

pub const ClientActor = struct {
    id: u32,
    allocator: std.mem.Allocator,
    network: *Network,
    prng: PRNG,
    num_replicas: u32,
    client_request_probability: f32,

    // TODO: Add state for tracking pending operations & verification

    pub fn init(allocator: std.mem.Allocator, id: u32, network: *Network, prng_seed: u64, num_replicas: u32, client_request_probability: f32) ClientActor {
        log.info("Initializing Client {}", .{id});
        if (num_replicas == 0) @panic("Client needs at least one replica to target");
        return ClientActor{
            .allocator = allocator,
            .id = id,
            .network = network,
            .prng = PRNG.init(prng_seed),
            .num_replicas = num_replicas,
            .client_request_probability = client_request_probability,
        };
    }

    pub fn deinit(self: *ClientActor) void {
        log.info("Deinitializing Client {}", .{self.id});
    }

    pub fn handleMessage(self: *ClientActor, message: messages.SimMessage, current_tick: u32) !void {
        _ = current_tick;
        log.debug("Client {} received message type {any} from {}", .{ self.id, message.payload, message.source_id });

        switch (message.payload) {
            .Response => |res_payload| {
                switch (res_payload) {
                    .Put => |put_res| {
                        log.info("Client {} received PutResponse: {}", .{ self.id, put_res.status });
                    },
                    .Get => |get_res| {
                        log.info("Client {} received GetResponse: {} (Value: {?s})", .{
                            self.id,
                            get_res.status,
                            get_res.value,
                        });
                    },
                }
                // TODO: Match with pending op, verify history
            },
            .Request => {
                log.warn("Client {} received unexpected Request message", .{self.id});
            },
        }
    }

    pub fn step(self: *ClientActor, current_tick: u32) !void {
        // Early return if float is outside probability
        if (self.prng.random().float(f32) > self.client_request_probability) {
            return;
        }

        // TODO Limit keys to up to 100, this is hard-coded, will adjust at a later time
        // Basically want a high hit rate for now
        // Use uintAtMostBiased for O(1) return and deterministic output
        const key_num = self.prng.random().uintAtMostBiased(u8, 100);

        // Keys should be only 8 bytes long, will be ok since key_name is max key_100 which is seven bytes including \0
        var key_ptr: [8]u8 = undefined;
        const key_name: []u8 = try std.fmt.bufPrint(&key_ptr, "key_{d}", .{key_num});

        const target_replica_id = self.prng.random().uintLessThanBiased(u32, self.num_replicas);

        var request_payload: messages.RequestPayload = undefined;

        // Send PUT request if is_put is true, else send GET
        const is_put = self.prng.random().boolean();
        if (is_put) {
            // Generate random value
            const val_num = self.prng.random().uintAtMostBiased(u32, 1_000_000);
            var val_ptr: [64]u8 = undefined;
            const val_str = try std.fmt.bufPrint(&val_ptr, "val_client_{d}_tick_{d}_rand_{d}", .{ self.id, current_tick, val_num });

            log.debug("Client {} sending PUT key='{s}' val='{s}' to replica {}", .{ self.id, key_name, val_str, target_replica_id });
            request_payload = .{ .Put = .{ .client_id = self.id, .key = key_name, .value = val_str } };
        } else {
            // Else request is get
            std.log.debug("Client {} sending GET key='{s}' to replica {}", .{ self.id, key_name, target_replica_id });

            request_payload = .{ .Get = .{ .client_id = self.id, .key = key_name } };
        }

        // const message = messages.SimMessage{ .source_id = self.id, .target_id = target_replica_id, .payload = .{ .Request = request_payload } };
        // try self.network.sendMessage(self.id, target_replica_id, message, current_tick);
    }
};
