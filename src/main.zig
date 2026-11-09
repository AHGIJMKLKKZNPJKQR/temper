const std = @import("std");
const sensor = @import("sensor.zig");
const config = @import("config.zig");
const notify = @import("notify.zig");

const Io = std.Io;
const http = std.http;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const cfg = try config.readConfigFromEnv(init.environ_map, io, gpa);
    const sensor_file = sensor.setupSensor(cfg, io) catch |err| {
        std.log.err("failed to setup sensor: {}", .{err});
        return err;
    };
    defer sensor_file.close(io);

    var http_client: http.Client = .{ .io = io, .allocator = gpa };
    defer http_client.deinit();
    const notifier: notify.Notifier = .{
        .http_client = &http_client,
        .base_url = cfg.ntfy_url,
        .auth = cfg.ntfy_auth,
    };

    while (true) {
        const temperature_mc = sensor.readTemperatureMilliCelsius(sensor_file, io) catch |err| {
            std.log.warn("failed to read temperature: {}", .{err});
            continue;
        };

        notify.maybeSendTemperatureAlert(
            notifier,
            temperature_mc,
            cfg.min_temperature_mc,
            cfg.max_temperature_mc,
        ) catch |err| {
            std.log.warn("failed to send notification: {}", .{err});
            continue;
        };
        // only send heartbeat when reading succeeded
        notify.sendHeartbeat(notifier, .fromMilliseconds(cfg.poll_interval_ms * cfg.heartbeat_fails_before_alert)) catch |err| {
            std.log.warn("failed to send heartbeat: {}", .{err});
        };

        try Io.sleep(io, .fromMilliseconds(cfg.poll_interval_ms), Io.Clock.awake);
    }
}
