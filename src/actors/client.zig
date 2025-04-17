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

    // TODO: Add state for tracking pending operations & verification

    pub fn init(allocator: std.mem.Allocator, id: u32, network: *Network, prng_seed: u64, num_replicas: u32) ClientActor {
        log.info("Initializing Client {}", .{id});
        if (num_replicas == 0) @panic("Client needs at least one replica to target");
        return ClientActor{
            .allocator = allocator,
            .id = id,
            .network = network,
            .prng = PRNG.init(prng_seed),
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
        if (self.prng.random().float(f32) < 0.1) {
            const is_put = self.prng.random().boolean();
            const key_num = self.prng.random().uintLessThan(u64, 100);
            var key_buf: [32]u8 = undefined;
            const key_stack_slice = std.fmt.bufPrint(&key_buf, "key_{d}", .{key_num}) catch |err| {
                log.err("Client {} failed to format key: {}", .{ self.id, err });
                return;
            };

            // --- Allocate heap copies ---
            const key_heap_copy = try self.allocator.dupe(u8, key_stack_slice);
            // Ensure heap copy is freed if subsequent operations fail
            errdefer self.allocator.free(key_heap_copy);

            var val_heap_copy: ?[]u8 = null; // Use optional for value
            if (is_put) {
                const val_num = self.prng.random().uintLessThan(u64, 1_000_000);
                var val_buf: [64]u8 = undefined;
                const val_stack_slice = std.fmt.bufPrint(&val_buf, "val_client{d}_tick{d}_rand{d}", .{ self.id, current_tick, val_num }) catch |err| {
                    log.err("Client {} failed to format value: {}", .{ self.id, err });
                    // Don't forget to free the already allocated key copy before returning
                    // errdefer already handles this
                    return;
                };
                val_heap_copy = try self.allocator.dupe(u8, val_stack_slice);
                // Ensure val copy is freed if message sending fails
                errdefer if (val_heap_copy) |v| self.allocator.free(v);
            }
            // --- Copies allocated ---

            const target_replica_id = self.prng.random().uintLessThan(u32, self.num_replicas);
            var request_payload: messages.RequestPayload = undefined;

            if (is_put) {
                // We checked above that val_heap_copy is non-null if is_put is true
                const value = val_heap_copy.?;
                log.debug("Client {} sending PUT key='{s}' val='{s}' to replica {}", .{ self.id, key_heap_copy, value, target_replica_id });
                request_payload = .{
                    .Put = .{
                        .client_id = self.id,
                        .key = key_heap_copy, // Pass heap copy
                        .value = value, // Pass heap copy
                    },
                };
            } else {
                log.debug("Client {} sending GET key='{s}' to replica {}", .{ self.id, key_heap_copy, target_replica_id });
                request_payload = .{
                    .Get = .{
                        .client_id = self.id,
                        .key = key_heap_copy, // Pass heap copy
                    },
                };
            }

            // The message now contains slices pointing to heap memory owned by the message/scheduler.
            const message = messages.SimMessage{
                .source_id = self.id,
                .target_id = target_replica_id,
                .payload = .{ .Request = request_payload },
            };

            // Try sending the message. If this fails, the errdefers above will free the copies.
            try self.network.sendMessage(self.id, target_replica_id, message, current_tick);

            // If sendMessage succeeds, ownership of the heap copies (key_heap_copy, val_heap_copy)
            // has been transferred to the message/event system. We no longer free them here.
            // The errdefers will NOT run on the success path.

            // TODO: Record operation invocation in history logger
        }
    }
};
