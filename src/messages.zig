const std = @import("std");
const log = std.log.scoped(.message); // Add logger

// --- Requests ---

pub const PutRequest = struct {
    client_id: u32,
    key: []const u8, // Will hold heap-allocated copy
    value: []const u8, // Will hold heap-allocated copy
};

pub const GetRequest = struct {
    client_id: u32,
    key: []const u8, // Will hold heap-allocated copy
};

pub const RequestPayload = union(enum) {
    Put: PutRequest,
    Get: GetRequest,
};

// --- Responses ---

pub const ResponseStatus = enum {
    Ok,
    Error, // Generic error for now
    NotFound, // Specific to Get
};

pub const PutResponse = struct {
    status: ResponseStatus,
};

pub const GetResponse = struct {
    status: ResponseStatus,
    value: ?[]u8, // Owned by receiver (client), allocated by sender (replica)
};

pub const ResponsePayload = union(enum) {
    Put: PutResponse,
    Get: GetResponse,
};

// --- Top-Level Message ---

pub const MessagePayload = union(enum) {
    Request: RequestPayload,
    Response: ResponsePayload,
};

pub const SimMessage = struct {
    source_id: u32,
    target_id: u32,
    payload: MessagePayload,

    pub fn deinitPayload(self: *SimMessage, allocator: std.mem.Allocator) void {
        log.debug("Deiniting message payload from {} to {}", .{ self.source_id, self.target_id });
        switch (self.payload) {
            .Request => |*req| switch (req.*) {
                // Free the heap-allocated key/value slices from requests
                .Put => |*put_req| {
                    log.debug("Freeing PutRequest key (len {}) and value (len {})", .{ put_req.key.len, put_req.value.len });
                    allocator.free(put_req.key);
                    allocator.free(put_req.value);
                    // Null out to prevent double free if struct is reused (unlikely here)
                    put_req.key = "";
                    put_req.value = "";
                },
                .Get => |*get_req| {
                    log.debug("Freeing GetRequest key (len {})", .{get_req.key.len});
                    allocator.free(get_req.key);
                    get_req.key = "";
                },
            },
            .Response => |*res| switch (res.*) {
                // Free the potentially heap-allocated value slice from GetResponse
                .Put => {}, // No allocated data in PutResponse
                .Get => |*get_res| {
                    if (get_res.value) |v| {
                        log.debug("Freeing GetResponse value (len {})", .{v.len});
                        allocator.free(v);
                        get_res.value = null;
                    }
                },
            },
        }
    }
};
