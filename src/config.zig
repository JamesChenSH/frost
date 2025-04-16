const std = @import("std");

pub const default_max_ticks: u32 = 1_000_000;
pub const default_num_replicas: u32 = 3;
pub const default_num_clients: u32 = 2;
pub const default_replica_pause_probability: f32 = 0.001;
pub const default_replica_resume_probability: f32 = 0.5;
pub const default_replica_crash_probability: f32 = 0.0005;

pub const SimulationConfig = struct {
    seed: u64,
    max_ticks: u32,
    num_replicas: u32,
    num_clients: u32,
    replica_pause_probability: f32,
    replica_resume_probability: f32,
    // TODO: We are not gonna mock replica crash probability yet, we are gonna use pause instead
    // replica_crash_probability: f32,
    // TODO: Add network latency config (min/max)
    // TODO: Add network partition config
    // TODO: Add DB-specific options (union based on target DB)
    // TODO: Add workload configuration

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.writeAll("Config{\n");
        try writer.print("\tseed: {},\n", .{self.seed});
        try writer.print("\tmax_ticks: {},\n", .{self.max_ticks});
        try writer.print("\tnum_replicas: {},\n", .{self.num_replicas});
        try writer.print("\tnum_clients: {},\n", .{self.num_clients});
        try writer.print("\treplica_pause_probability: {d},\n", .{self.replica_pause_probability});
        try writer.print("\treplica_resume_probability: {d},\n", .{self.replica_resume_probability});
        try writer.writeAll("}");
    }
};

// Potential future function for loading from file
// pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !SimulationConfig { ... }
