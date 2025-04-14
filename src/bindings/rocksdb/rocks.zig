const std = @import("std");

const rdb = @cImport({
    @cInclude("rocksdb/c.h");
});

const RocksDB = struct {
    db: *rdb.rocksdb_t,

    fn open(dir: []const u8) struct { val: ?RocksDB, err: ?[]u8 } {
        const options: ?*rdb.rocksdb_options_t = rdb.rocksdb_options_create();
        rdb.rocksdb_options_set_create_if_missing(options, 1);
        var err: ?[*]u8 = null;
        const db: ?*rdb.rocksdb_t = rdb.rocksdb_open(options, dir.ptr, &err);
        if (err) |err_ptr| {
            var len: usize = 0;
            while (err_ptr[len] != 0) {
                len += 1;
            }
            const error_slice: []u8 = err_ptr[0..len];

            return .{ .val = null, .err = error_slice };
        } else {
            return .{ .val = null, .err = "" };
        }
        return .{ .val = RocksDB{ .db = db.? }, .err = null };
    }

    fn close(self: RocksDB) void {
        rdb.rocksdb_close(self.db);
    }

    fn set(self: RocksDB, key: [:0]const u8, value: [:0]const u8) ?[]u8 {
        const writeOptions = rdb.rocksdb_writeoptions_create();
        var err: ?[*]u8 = null;
        rdb.rocksdb_put(
            self.db,
            writeOptions,
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

            return error_slice;
        }

        return null;
    }

    fn get(self: RocksDB, key: [:0]const u8) struct { val: ?[]u8, err: ?[]u8 } {
        const readOptions = rdb.rocksdb_readoptions_create();
        var valueLength: usize = 0;
        var err: ?[*]u8 = null;
        var v = rdb.rocksdb_get(
            self.db,
            readOptions,
            key.ptr,
            key.len,
            &valueLength,
            &err,
        );
        if (err) |err_ptr| {
            var len: usize = 0;
            while (err_ptr[len] != 0) {
                len += 1;
            }
            const error_slice: []u8 = err_ptr[0..len];

            return .{ .val = null, .err = error_slice };
        }
        if (v == 0) {
            return .{ .val = null, .err = null };
        }

        return .{ .val = v[0..valueLength], .err = null };
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

        fn close(self: Iter) void {
            rdb.rocksdb_iter_destroy(self.iter);
        }
    };

    fn iter(self: RocksDB, prefix: [:0]const u8) struct { val: ?Iter, err: ?[]const u8 } {
        const readOptions = rdb.rocksdb_readoptions_create();
        var it = Iter{
            .iter = undefined,
            .first = true,
            .prefix = prefix,
        };
        if (rdb.rocksdb_create_iterator(self.db, readOptions)) |i| {
            it.iter = i;
        } else {
            return .{ .val = null, .err = "Could not create iterator" };
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
        return .{ .val = it, .err = null };
    }
};

pub fn main() !void {
    std.log.info("123", .{});
    const openRes = RocksDB.open("/tmp/db");
    if (openRes.err) |err| {
        std.debug.print("Failed to open: {s}.\n", .{err});
    }
    var db = openRes.val.?;
    defer db.close();

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
        const setErr = db.set(key, value);
        if (setErr) |err| {
            std.debug.print("Error setting key: {s}.\n", .{err});
            return;
        }
    } else if (std.mem.eql(u8, command, "get")) {
        const getRes = db.get(key);
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
        defer iter.close();
        while (iter.next()) |entry| {
            std.debug.print("{s} = {s}\n", .{ entry.key, entry.value });
        }
    }
}
