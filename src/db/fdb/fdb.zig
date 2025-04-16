const std = @import("std");

const fdb = @cImport({
    // Define API version
    @cDefine("FDB_API_VERSION", "730");
    @cInclude("foundationdb/fdb_c.h");
});

// DEBUG_HELPERS
pub fn checkError(err: fdb.fdb_error_t) void {
    if (err != 0) {
        std.log.info("Error {}: {*}\n", .{ err, fdb.fdb_get_error(err) });
    }
}

// MultiThread to run the network
pub fn networkRuner() void {}

const fdb_bridge = struct {
    db: *fdb.FDBDatabase = undefined,

    // Function to initialize the FDB library
    pub fn init() !void {
        const x = fdb.fdb_select_api_version(730);
        std.log.info("{}\n", .{x});
        checkError(fdb.fdb_setup_network());
        std.log.info("Created Network", .{});
    }

    // Function to create a new database instance
    pub fn create_database(self: fdb_bridge) *fdb.FDBDatabase {
        // Naming this db_opt since it's an optional
        var db_opt: ?*fdb.FDBDatabase = undefined;
        checkError(fdb.fdb_create_database("/etc/foundationdb/fdb.cluster", &db_opt));

        // If db_opt is non-null, bind it to db_ptr
        // which will have type *fdb.FDBDatabase
        if (db_opt) |db_ptr| {
            std.log.info("Created database pointer: {*any}", .{db_ptr});
            self.db = db_ptr;
        }
        std.log.err("fdb_create_database succeeded but returned a null pointer", .{});
        std.process.exit(1);
    }

    // Function to destroy the database instance
    pub fn destroy_database(self: fdb_bridge) void {
        fdb.fdb_database_destroy(self.db);
    }

    // Function to get the version of the FDB library
    pub fn get_version() u32 {
        return fdb.fdb_get_version();
    }

    pub fn run_network() void {
        // Run the network in a separate thread
        checkError(fdb.fdb_run_network());
        std.log.info("Running Network on sub-Thread", .{});
    }

    pub fn end_network(thread: std.Thread) void {
        checkError(fdb.fdb_stop_network());
        thread.join();
        std.log.info("Network stopped", .{});
    }
};

pub fn createDataInDatabase(
    db: *fdb.FDBDatabase,
    key: []const u8,
    value: []const u8,
) void {
    var transaction: ?*fdb.FDBTransaction = undefined;
    checkError(fdb.fdb_database_create_transaction(db, &transaction));

    // Remember to destroy the transaction after use
    defer fdb.fdb_transaction_destroy(transaction);

    // Set key and value to store
    // Get length of key and value
    fdb.fdb_transaction_set(transaction, @as([*c]const u8, key.ptr), @as(c_int, @intCast(key.len)), @as([*c]const u8, value.ptr), @as(c_int, @intCast(value.len)));

    // Commit the transaction
    var commited: c_int = 0;
    while (commited == 0) {
        const commit_future = fdb.fdb_transaction_commit(transaction);
        checkError(fdb.fdb_future_block_until_ready(commit_future));

        if (fdb.fdb_future_get_error(commit_future) != 0) {
            // Handle commit error
            const commit_future_err = fdb.fdb_transaction_on_error(transaction, fdb.fdb_future_get_error(commit_future));
            checkError(fdb.fdb_future_block_until_ready(commit_future_err));
            const err2 = fdb.fdb_future_get_error(commit_future_err);
            if (err2 != 0) {
                checkError(err2);
            }
        } else {
            commited = 1;
        }
        fdb.fdb_future_destroy(commit_future);
    }
}

pub fn readFromDatabase(
    db: *fdb.FDBDatabase,
    key: []const u8,
) ![*c]const u8 {
    // Init needed null variables
    var valuePresent: fdb.fdb_bool_t = undefined;
    var value: [*c]const u8 = undefined;
    var value_length: c_int = 0;

    // Create an empty transaction
    var transaction: ?*fdb.FDBTransaction = undefined;
    checkError(fdb.fdb_database_create_transaction(db, &transaction));

    // Remember to destroy the transaction after use.
    defer fdb.fdb_transaction_destroy(transaction);

    // Get the value for the key
    const getFuture: *fdb.FDBFuture = fdb.fdb_transaction_get(transaction, @as([*c]const u8, key.ptr), @as(c_int, @intCast(key.len)), 0).?;
    checkError(fdb.fdb_future_block_until_ready(getFuture));
    const err2 = fdb.fdb_future_get_error(getFuture);
    if (err2 != 0) {
        checkError(err2);
    }

    checkError(
        fdb.fdb_future_get_value(getFuture, &valuePresent, &value, &value_length),
    );

    std.log.info("Got value from db. {*}: '{}{*}'\n", .{ key, value_length, value });

    fdb.fdb_future_destroy(getFuture);
    return value;
}

pub fn main() !void {

    // Initialize the FDB library
    try fdb_bridge.init();
    std.log.info("FDB Network Initialized", .{});

    // Run the network in a separate thread
    const network_thread = try std.Thread.spawn(.{}, fdb_bridge.run_network, .{});

    // Create a new database instance
    const db = fdb_bridge.create_database();

    defer fdb_bridge.destroy_database(db);

    // Example key-value pair
    const key = "example_key";
    const value = "example_value";

    // Create data in the database
    createDataInDatabase(db, key, value);

    // Read data from the database
    const read_value = try readFromDatabase(db, key);
    std.log.info("Read value: '{*}'\n", .{read_value});

    std.log.info("Finish testing! Looks Great.", .{});

    // End the network
    fdb_bridge.end_network(network_thread);
    // Destroy the database
    fdb_bridge.destroy_database(db);
}
