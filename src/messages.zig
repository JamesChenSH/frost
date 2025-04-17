const std = @import("std");

// --- Requests ---

pub const PutRequest = struct {
    client_id: u32, // ID of the client sending the request
    key: []const u8,
    value: []const u8,
};

pub const GetRequest = struct {
    client_id: u32,
    key: []const u8,
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

    // Function to help free payload contents if needed
    // Caller needs the allocator used for the contents.
    pub fn deinitPayload(self: *SimMessage, allocator: std.mem.Allocator) void {
        switch (self.payload) {
            .Request => |*req| switch (req.*) {
                // Keys/Values in requests are passed as slices owned by the sender (client)
                // and are freed there after the message is handled or copied.
                // No freeing needed here assuming receiver doesn't store the slices long-term.
                .Put => {},
                .Get => {},
            },
            .Response => |*res| switch (res.*) {
                // Value in GetResponse is allocated by the sender (replica)
                // and needs to be freed by the receiver (client) or during event cleanup.
                .Put => {},
                .Get => |*get_res| {
                    if (get_res.value) |v| {
                        allocator.free(v);
                        get_res.value = null; // Avoid double free
                    }
                },
            },
        }
    }
};
