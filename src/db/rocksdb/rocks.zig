const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.rocksdb);

const rdb = @cImport({
    @cInclude("rocksdb/c.h");
});

/// Errors specific to RocksDB operations.
pub const RocksDBError = error{
    OpenFailed,
    CloseFailed, // Although deinit returns void, an error could theoretically occur
    PutFailed,
    GetFailed,
    NotFound, // Specific error for key not found in Get
    OptionsCreationFailed,
    DatabasePathError, // Error converting path to C string
    MemoryAllocationFailed,
    NotInitialized, // If trying to use a deinitialized instance,
    IteratorFailed,
};

pub const RocksDB = struct {
    options: ?*rdb.rocksdb_options_t = null, // Only needed during init
    write_options: ?*rdb.rocksdb_writeoptions_t = null,
    read_options: ?*rdb.rocksdb_readoptions_t = null,
    db: ?*rdb.rocksdb_t = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator, dir: []const u8) !RocksDB {
        log.debug("Initializing RocksDB at path: {s}", .{dir});

        var self = RocksDB{ .allocator = allocator };

        self.options = rdb.rocksdb_options_create();
        if (self.options == null) {
            return error.OptionsCreationFailed;
        }

        rdb.rocksdb_options_set_create_if_missing(self.options.?, 1);

        // Options Operations
        self.write_options = rdb.rocksdb_writeoptions_create();
        if (self.write_options == null) {
            return error.OptionsCreationFailed;
        }
        defer if (self.db == null and self.write_options != null) {
            rdb.rocksdb_writeoptions_destroy(self.write_options.?);
        };
        self.read_options = rdb.rocksdb_readoptions_create();
        if (self.read_options == null) {
            return error.OptionsCreationFailed;
        }
        defer if (self.db == null and self.read_options != null) {
            rdb.rocksdb_readoptions_destroy(self.read_options.?);
        };

        const c_db_path = try allocator.allocSentinel(u8, dir.len, 0);
        defer allocator.free(c_db_path);
        @memcpy(c_db_path.ptr[0..dir.len], dir);

        var err: ?[*]u8 = null;
        self.db = rdb.rocksdb_open(self.options.?, c_db_path.ptr, &err);
        if (err) |err_ptr| {
            var len: usize = 0;
            while (err_ptr[len] != 0) {
                len += 1;
            }
            const error_slice: []u8 = err_ptr[0..len];
            log.debug("error: {s}", .{error_slice});
            self.db = null;
            return error.OpenFailed;
        } else {
            log.info("Opened DB at {s} successfully", .{dir});
            return self;
        }
    }

    pub fn deinit(self: *RocksDB) void {
        if (self.db) |db_handle| {
            rdb.rocksdb_close(db_handle);
            self.db = null;
        }
        if (self.write_options) |wo| {
            rdb.rocksdb_writeoptions_destroy(wo);
            self.write_options = null;
        }
        if (self.read_options) |ro| {
            rdb.rocksdb_readoptions_destroy(ro);
            self.read_options = null;
        }
        if (self.options) |opt| {
            rdb.rocksdb_options_destroy(opt);
            self.options = null;
        }
    }

    pub fn put(self: *RocksDB, key: []const u8, value: []const u8) !void {
        var err: ?[*]u8 = null;
        rdb.rocksdb_put(
            self.db,
            self.write_options,
            key.ptr,
            key.len,
            value.ptr,
            value.len,
            &err,
        );
        if (err) |err_ptr| {
            var len: usize = 0;
            while (err_ptr[len] != 0) {
                len += 1;
            }
            const error_slice: []u8 = err_ptr[0..len];
            log.err("Error: {s}", .{error_slice});
            return error.PutFailed;
        }
    }

    pub fn get(self: *RocksDB, key: []const u8, allocator: Allocator) !?[]u8 {
        var valueLength: usize = 0;
        var err_ptr: ?[*]u8 = null;
        var v = rdb.rocksdb_get(
            self.db,
            self.read_options,
            key.ptr,
            key.len,
            &valueLength,
            &err_ptr,
        );
        if (err_ptr) |err| {
            defer rdb.rocksdb_free(err);
            var len: usize = 0;
            while (err[len] != 0) {
                len += 1;
            }
            const error_slice: []u8 = err[0..len];
            log.err("Error: {s}", .{error_slice});
            rdb.rocksdb_free(v);

            return error.GetFailed;
        }
        if (v == 0) {
            return error.NotFound;
        }

        const value_slice = allocator.alloc(u8, valueLength) catch |err| {
            std.log.err("Failed to allocate memory for RocksDB get result: {}", .{err});
            // Must still free result_ptr if allocation fails! The defer handles this.
            return error.MemoryAllocationFailed;
        };

        @memcpy(value_slice, v[0..valueLength]);

        return value_slice;
    }

    const IterEntry = struct {
        key: []const u8,
        value: []const u8,
    };

    const Iter = struct {
        iter: *rdb.rocksdb_iterator_t,
        first: bool,
        prefix: []const u8,

        fn next(self: *Iter) ?IterEntry {
            if (!self.first) {
                rdb.rocksdb_iter_next(self.iter);
            }

            self.first = false;
            if (rdb.rocksdb_iter_valid(self.iter) != 1) {
                return null;
            }

            var keySize: usize = 0;
            var key = rdb.rocksdb_iter_key(self.iter, &keySize);

            // Make sure key is still within the prefix
            if (self.prefix.len > 0) {
                if (self.prefix.len > keySize or
                    !std.mem.eql(u8, key[0..self.prefix.len], self.prefix))
                {
                    return null;
                }
            }

            var valueSize: usize = 0;
            var value = rdb.rocksdb_iter_value(self.iter, &valueSize);

            return IterEntry{
                .key = key[0..keySize],
                .value = value[0..valueSize],
            };
        }

        fn deinit(self: Iter) void {
            rdb.rocksdb_iter_destroy(self.iter);
        }
    };

    pub fn iter(self: *RocksDB, prefix: [:0]const u8) !?Iter {
        const readOptions = rdb.rocksdb_readoptions_create();
        var it = Iter{
            .iter = undefined,
            .first = true,
            .prefix = prefix,
        };
        if (rdb.rocksdb_create_iterator(self.db, readOptions)) |i| {
            it.iter = i;
        } else {
            log.err("Error: Iterator Creation Failed", .{});
            return error.IteratorFailed;
        }

        if (prefix.len > 0) {
            rdb.rocksdb_iter_seek(
                it.iter,
                prefix.ptr,
                prefix.len,
            );
        } else {
            rdb.rocksdb_iter_seek_to_first(it.iter);
        }
        return it;
    }
};

pub fn main() !void {
    const openRes = RocksDB.init("/users/chens266/project/frost/src/db/rocksdb/tmp/db");
    if (openRes.err) |err| {
        std.debug.print("Failed to open: {s}.\n", .{err});
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var db = openRes.val.?;
    defer db.deinit();

    var args = std.process.args();
    _ = args.next();
    var key: [:0]const u8 = "";
    var value: [:0]const u8 = "";
    var command = "get";
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "set")) {
            command = "set";
            key = args.next().?;
            value = args.next().?;
        } else if (std.mem.eql(u8, arg, "get")) {
            command = "get";
            key = args.next().?;
        } else if (std.mem.eql(u8, arg, "list")) {
            command = "lst";
            if (args.next()) |argNext| {
                key = argNext;
            }
        } else {
            std.debug.print("Must specify command (get, set, or list). Got: '{s}'.\n", .{arg});
            return;
        }
    }

    if (std.mem.eql(u8, command, "set")) {
        const setErr = db.put(key, value);
        if (setErr) |err| {
            std.debug.print("Error setting key: {s}.\n", .{err});
            return;
        }
    } else if (std.mem.eql(u8, command, "get")) {
        const getRes = db.get(key, allocator);
        if (getRes.err) |err| {
            std.debug.print("Error getting key: {s}.\n", .{err});
            return;
        }

        if (getRes.val) |v| {
            std.debug.print("{s}\n", .{v});
        } else {
            std.debug.print("Key not found.\n", .{});
        }
    } else {
        const prefix = key;
        const iterRes = db.iter(prefix);
        if (iterRes.err) |err| {
            std.debug.print("Error getting iterator: {s}.\n", .{err});
        }
        var iter = iterRes.val.?;
        defer iter.deinit();
        while (iter.next()) |entry| {
            std.debug.print("{s} = {s}\n", .{ entry.key, entry.value });
        }
    }
}
