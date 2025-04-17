const std = @import("std");
const log = std.log.scoped(.client);

const Network = @import("../network.zig").Network;
const PRNG = @import("../prng.zig").PRNG;
const messages = @import("../messages.zig");

pub const ClientActor = struct {
    id: u32,
    allocator: std.mem.Allocator,
    network: *Network,
    prng: *PRNG, // For choosing operations/keys
    num_replicas: u32,

    // TODO: Add state for tracking pending operations & verification

    pub fn init(allocator: std.mem.Allocator, id: u32, network: *Network, prng: *PRNG, num_replicas: u32) ClientActor {
        log.info("Initializing Client {}", .{id});
        if (num_replicas == 0) @panic("Client needs at least one replica to target");
        return ClientActor{
            .allocator = allocator,
            .id = id,
            .network = network,
            .prng = prng,
            .num_replicas = num_replicas,
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
                        // IMPORTANT: Free the value slice if present.
                        if (get_res.value) |v| {
                            log.debug("Client {} freeing received value slice (len {})", .{ self.id, v.len });
                            self.allocator.free(v);
                        }
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
        // Workload: ~10% chance per tick to send one request
        if (self.prng.random().float(f32) < 0.1) {
            const is_put = self.prng.random().boolean();
            const key_num = self.prng.random().uintLessThan(u64, 100); // Smaller key space
            var key_buf: [32]u8 = undefined;
            // Using bufPrint is efficient but requires the buffer to be large enough.
            const key_slice = std.fmt.bufPrint(&key_buf, "key_{d}", .{key_num}) catch |err| {
                log.err("Failed to format key: {}", .{err});
                return; // Skip this step on formatting error
            };

            // Choose target replica
            const target_replica_id = self.prng.random().uintLessThan(u32, self.num_replicas);

            var request_payload: messages.RequestPayload = undefined;
            var temp_val_slice: ?[]u8 = null; // Hold temp value slice if needed

            if (is_put) {
                const val_num = self.prng.random().uintLessThan(u64, 1_000_000);
                var val_buf: [64]u8 = undefined; // Larger buffer for value
                const val_slice = std.fmt.bufPrint(&val_buf, "val_client{d}_tick{d}_rand{d}", .{ self.id, current_tick, val_num }) catch |err| {
                    log.err("Failed to format value: {}", .{err});
                    return;
                };
                temp_val_slice = val_slice; // Keep track for logging if needed

                log.debug("Client {} sending PUT key='{s}' val='{s}' to replica {}", .{ self.id, key_slice, val_slice, target_replica_id });

                request_payload = .{
                    .Put = .{
                        .client_id = self.id,
                        // Pass slices directly. Assumes they live long enough. See memory note below.
                        .key = key_slice,
                        .value = val_slice,
                    },
                };
            } else {
                log.debug("Client {} sending GET key='{s}' to replica {}", .{ self.id, key_slice, target_replica_id });
                request_payload = .{ .Get = .{
                    .client_id = self.id,
                    .key = key_slice,
                } };
            }

            // Memory Safety Note: We are passing slices (key_slice, val_slice) that point
            // to memory on this function's stack (`key_buf`, `val_buf`). This is ONLY safe
            // because:
            // 1. Network latency is very low (1-5 ticks).
            // 2. Scheduler processes events promptly.
            // 3. Replica `handleMessage` processes the request immediately and doesn't store the slices.
            // If latency increases or replicas queue requests, these stack buffers might be invalid
            // by the time the message is processed.
            // A robust solution MUST allocate copies of the key/value on the heap (using self.allocator)
            // and pass those copies in the message. The receiving side (replica or message system)
            // would then be responsible for freeing those copies.
            const message = messages.SimMessage{
                .source_id = self.id,
                .target_id = target_replica_id,
                .payload = .{ .Request = request_payload },
            };

            try self.network.sendMessage(self.id, target_replica_id, message, current_tick);

            // TODO: Record operation invocation in history logger
        }
    }
};
