const std = @import("std");

const Allocator = std.mem.Allocator;
const Uri = std.Uri;
const Io = std.Io;
const Dir = Io.Dir;
const Environ = std.process.Environ;

pub const Config = struct {
    poll_interval_ms: u32,
    heartbeat_fails_before_alert: u32,
    min_temperature_mc: i32,
    max_temperature_mc: i32,
    ntfy_url: Uri,
    ntfy_auth: []const u8,
    sensor_directory: Dir,
};

pub fn readConfigFromEnv(env_map: *Environ.Map, io: Io, gpa: Allocator) !Config {
    const heartbeat_fails_before_alert = try readInt(u32, env_map, "TMP_HEARTBEAT_FAILS_BEFORE_ALERT", 20);
    std.debug.assert(heartbeat_fails_before_alert > 0);

    const ntfy_token = try requiredEnv(env_map, "TMP_NTFY_TOKEN");
    const ntfy_auth = try gpa.print("Bearer {s}", .{ntfy_token});

    return .{
        .poll_interval_ms = try readInt(u32, env_map, "TMP_POLL_INTERVAL_MS", 15_000),
        .heartbeat_fails_before_alert = heartbeat_fails_before_alert,
        .min_temperature_mc = try readInt(i32, env_map, "TMP_MIN_TEMPERATURE_MC", 3_000),
        .max_temperature_mc = try readInt(i32, env_map, "TMP_MAX_TEMPERATURE_MC", 7_000),
        .ntfy_url = try Uri.parse(try requiredEnv(env_map, "TMP_NTFY_URL")),
        .ntfy_auth = ntfy_auth,
        .sensor_directory = try Dir.openDirAbsolute(io, try requiredEnv(env_map, "TMP_SENSOR_DIRECTORY"), .{}),
    };
}

fn requiredEnv(env_map: *Environ.Map, key: []const u8) ![]const u8 {
    return env_map.get(key) orelse {
        std.log.err("Missing required environment variable: {s}", .{key});
        return error.RequiredEnvMissing;
    };
}

fn readInt(T: type, env_map: *Environ.Map, key: []const u8, default: T) !T {
    if (env_map.get(key)) |value_raw|
        return try std.fmt.parseInt(T, value_raw, 10)
    else
        return default;
}
