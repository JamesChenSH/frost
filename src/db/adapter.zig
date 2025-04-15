// src/db/adapter.zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.db_adapter);

// Import the concrete database implementations we want to adapt
const rocksdb_binding = @import("./bindings/rocksdb/rocks.zig");
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
};

/// The generic Database Adapter.
/// Callers interact with this struct, which dispatches calls
/// to the appropriate concrete implementation stored in `impl`.
pub const DbAdapter = struct {
    impl: DbImpl,
    allocator: Allocator, // Store allocator for deinit and potential other uses

    // --- Public Methods ---

    /// Initializes the database adapter with the specified backend type and config.
    pub fn init(allocator: Allocator, db_type: DbType, config: DbConfig) !DbAdapter {
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

        return DbAdapter{
            .impl = db_impl,
            .allocator = allocator,
        };
    }

    /// Deinitializes the adapter and releases resources held by the underlying database.
    pub fn deinit(self: *DbAdapter) void {
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
    pub fn put(self: *DbAdapter, key: []const u8, value: []const u8) DbError!void {
        return self.impl.put(key, value);
    }

    /// Gets a value associated with a key from the database.
    /// Returns `null` if the key is not found.
    /// The caller owns the returned memory slice (if not null) and must free it
    /// using the provided `allocator`.
    pub fn get(self: *DbAdapter, key: []const u8, allocator: Allocator) DbError!?[]u8 {
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

    // --- Common methods dispatched by DbAdapter ---
    // These methods are defined on the union itself for convenient dispatch.

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
            .RocksDB => |*db| return db.get(self.RocksDB, key) catch |err| {
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

// --- Tests (Optional but Recommended) ---
// You would typically add tests here to verify the adapter works correctly,
// potentially using a mock or the actual RocksDB binding if dependencies allow.
// test "init and deinit RocksDB adapter" { ... }
// test "put and get via RocksDB adapter" { ... }
