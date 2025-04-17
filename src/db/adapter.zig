// src/db/adapter.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.db_adapter);

// Import the concrete database implementations we want to adapt
const rocksdb_binding = @import("./rocksdb/rocks.zig");
// const fdb_binding = @import("fdb_binding.zig"); // Example for the future

// --- Public Interface ---

/// Enum to specify which database backend to use.
pub const DbType = enum {
    RocksDB,
    // FoundationDB, // Example for the future
};

/// Generic configuration structure passed to init.
/// For now, we only handle the path needed by RocksDB.
/// This could be expanded into a union for more complex, type-specific configs.
pub const DbConfig = struct {
    path: []const u8,
    // Add other common config options here if needed,
    // or change this to a union for type-specific configs.
};

/// Error union for database operations via the adapter.
/// Currently uses anyerror for simplicity, could be refined later
/// to combine specific error sets from different backends.
pub const DbError = error{
    /// Error returned by the underlying database implementation.
    BackendError,
    /// An incompatible database type was requested for an operation.
    UnsupportedOperation,
    /// The requested database type is not compiled in or configured.
    UnknownDbType,
    /// The adapter or its underlying DB is not initialized.
    NotInitialized,
    /// DB is not found
    NotFound,
};

/// The generic Database Adapter.
/// Callers interact with this struct, which dispatches calls
/// to the appropriate concrete implementation stored in `impl`.
pub const DbInterfaces = struct {
    impl: DbImpl,
    allocator: Allocator, // Store allocator for deinit and potential other uses

    // --- Public Methods ---

    /// Initializes the database adapter with the specified backend type and config.
    pub fn init(allocator: Allocator, db_type: DbType, config: DbConfig) !DbInterfaces {
        log.info("Initializing DbAdapter with type: {} and path: {s}", .{ db_type, config.path });

        const db_impl = switch (db_type) {
            .RocksDB => DbImpl{
                .RocksDB = try rocksdb_binding.RocksDB.init(allocator, config.path),
            },
            // .FoundationDB => |cluster_file_path| { // Example
            //     return DbImpl{ .FoundationDB = try fdb_binding.FDB.init(allocator, cluster_file_path) };
            // },
            // Add other DB types here
            // else => return error.UnknownDbType, // if DbType allows it
        };

        return DbInterfaces{
            .impl = db_impl,
            .allocator = allocator,
        };
    }

    /// Deinitializes the adapter and releases resources held by the underlying database.
    pub fn deinit(self: *DbInterfaces) void {
        log.info("Deinitializing DbAdapter", .{});
        switch (self.impl) {
            .RocksDB => |*db| db.deinit(),
            // .FoundationDB => |*db| db.deinit(self.allocator), // FDB might need allocator
            // Add other DB types here
        }
        // Resetting the struct might be useful if it can be reused,
        // but usually, it's destroyed after deinit.
        // self.* = undefined; // Or some other marker
    }

    /// Puts a key-value pair into the database.
    pub fn put(self: *DbInterfaces, key: []const u8, value: []const u8) DbError!void {
        return self.impl.put(key, value);
    }

    /// Gets a value associated with a key from the database.
    /// Returns `null` if the key is not found.
    /// The caller owns the returned memory slice (if not null) and must free it
    /// using the provided `allocator`.
    pub fn get(self: *DbInterfaces, key: []const u8, allocator: Allocator) DbError!?[]u8 {
        // Pass the allocator needed for the result allocation
        return self.impl.get(key, allocator);
    }

    // --- Transaction Methods (Placeholder Examples) ---

    // pub fn beginTransaction(self: *DbAdapter) !TransactionAdapter {
    //     // ... dispatch based on self.impl ...
    // }

    // TODO: Add transaction methods later if needed.
    // The `TransactionAdapter` would follow a similar pattern.
};

// --- Internal Implementation Details ---

/// Tagged union holding the actual instance of the concrete database implementation.
const DbImpl = union(enum) {
    RocksDB: rocksdb_binding.RocksDB,
    // FoundationDB: fdb_binding.FDB, // Example for the future

    // --- Common methods dispatched by DbInterface ---

    fn put(self: *DbImpl, key: []const u8, value: []const u8) DbError!void {
        switch (self.*) {
            .RocksDB => |*db| return db.put(key, value) catch |err| {
                log.err("RocksDB put failed: {s}", .{@errorName(err)});
                return DbError.BackendError; // Wrap backend error
            },
            // .FoundationDB => |*db| return db.put(key, value),
            // else => return error.UnsupportedOperation, // Or handle appropriately
        }
    }

    fn get(self: *DbImpl, key: []const u8, allocator: Allocator) DbError!?[]u8 {
        std.log.info("{}", .{allocator});
        switch (self.*) {
            .RocksDB => |*db| return db.get(key, allocator) catch |err| {
                // Handle specific errors like NotFound vs other errors if possible
                if (err == rocksdb_binding.RocksDBError.NotFound) return null; // Map NotFound to null
                log.err("RocksDB get failed: {s}", .{@errorName(err)});
                return DbError.BackendError; // Wrap other backend errors
            },
            // .FoundationDB => |*db| return db.get(key, allocator),
            // else => return error.UnsupportedOperation, // Or handle appropriately
        }
    }
};

// --- Tests ---
// Ensure this is within the file scope, after the DbAdapter definition.
const testing = std.testing;
const fs = std.fs;
const cwd = std.fs.cwd();

test "DbAdapter init, deinit with RocksDB" {
    const allocator = testing.allocator;
    const test_db_path = "./test_adapter_init_deinit_db";

    // Ensure clean state before test
    _ = cwd.deleteTree(test_db_path) catch {}; // Ignore error if not exists
    defer { // Ensure cleanup after test
        _ = cwd.deleteTree(test_db_path) catch {};
    }

    const config = DbConfig{ .path = test_db_path };

    // Init
    var db_intf = try DbInterfaces.init(allocator, .RocksDB, config);
    // Check if the allocator was stored (simple check)
    // try testing.expect(adapter.allocator.raw_allocator == allocator.raw_allocator);
    // Check if the impl is RocksDB
    try testing.expect(db_intf.impl == .RocksDB);

    // Deinit (happens in defer)
    defer db_intf.deinit();

    // Check if the DB directory was created
    var dir = try cwd.openDir(test_db_path, .{});
    defer dir.close();
}

test "DbAdapter put and get with RocksDB" {
    const allocator = testing.allocator;
    const test_db_path = "./test_adapter_put_get_db";

    // Ensure clean state before test
    _ = cwd.deleteTree(test_db_path) catch {}; // Ignore error if not exists
    defer { // Ensure cleanup after test
        _ = cwd.deleteTree(test_db_path) catch {};
    }

    const config = DbConfig{ .path = test_db_path };
    var db_intf = try DbInterfaces.init(allocator, .RocksDB, config);
    defer db_intf.deinit();

    const key1 = "mykey";
    const val1 = "myvalue";
    const key2 = "anotherkey";
    const val2 = "anothervalue123";
    const key_notfound = "missingkey";

    // Put first key-value
    try db_intf.put(key1, val1);

    // Get first key-value
    const retrieved_val1 = try db_intf.get(key1, allocator);
    try testing.expect(retrieved_val1 != null);
    // IMPORTANT: Free the memory returned by get!
    defer if (retrieved_val1) |slice| allocator.free(slice);
    try testing.expectEqualStrings(val1, retrieved_val1.?);

    // Put second key-value
    try db_intf.put(key2, val2);

    // Get second key-value
    const retrieved_val2 = try db_intf.get(key2, allocator);
    try testing.expect(retrieved_val2 != null);
    defer if (retrieved_val2) |slice| allocator.free(slice);
    try testing.expectEqualStrings(val2, retrieved_val2.?);

    // Get first key again
    const retrieved_val1_again = try db_intf.get(key1, allocator);
    try testing.expect(retrieved_val1_again != null);
    defer if (retrieved_val1_again) |slice| allocator.free(slice);
    try testing.expectEqualStrings(val1, retrieved_val1_again.?);

    // Get non-existent key
    const retrieved_missing = try db_intf.get(key_notfound, allocator);
    try testing.expect(retrieved_missing == null);
    // No need to free if null
}

test "DbAdapter get non-existent key returns null" {
    const allocator = testing.allocator;
    const test_db_path = "./test_adapter_get_null_db";

    // Ensure clean state before test
    _ = cwd.deleteTree(test_db_path) catch {}; // Ignore error if not exists
    defer { // Ensure cleanup after test
        _ = cwd.deleteTree(test_db_path) catch {};
    }

    const config = DbConfig{ .path = test_db_path };
    var db_intf = try DbInterfaces.init(allocator, .RocksDB, config);
    defer db_intf.deinit();

    const key_notfound = "this_key_does_not_exist";

    const result = try db_intf.get(key_notfound, allocator);
    try testing.expect(result == null);
}
