const std = @import("std");
const http = std.http;
const config = @import("config.zig");

const Config = config.Config;
const Io = std.Io;
const Uri = std.Uri;
const Duration = Io.Duration;

pub const Notifier = struct {
    http_client: *http.Client,
    base_url: Uri,
    auth: []const u8,
};

pub const Notification = union(enum) {
    heartbeat,
    temperature_alert: struct { min: i32, max: i32, actual: i32 },
};

pub fn sendHeartbeat(notifier: Notifier, offset: Duration) !void {
    return ntfyReq(notifier.http_client, .{
        .priority = NtfyPriority.HIGH,
        .base_url = notifier.base_url,
        .auth = notifier.auth,
        .topic = "heartbeat",
        .title = "Heartbeat missed!",
        .body = "Stopped receiving heartbeat!",
        .sequence_id = "heartbeat",
        .offset = offset,
    });
}

pub fn maybeSendTemperatureAlert(notifier: Notifier, min_mc: i32, max_mc: i32, actual_mc: i32) !void {
    if (actual_mc > min_mc and actual_mc < max_mc) {
        return;
    }

    const actual_c = @as(f32, @floatFromInt(actual_mc)) / 1000.0;
    const min_c = @as(f32, @floatFromInt(min_mc)) / 1000.0;
    const max_c = @as(f32, @floatFromInt(max_mc)) / 1000.0;

    var buf: [128]u8 = undefined;
    const body = std.mem.print(
        &buf,
        "Temperature reading {d:.1} is outside of allowed range ({d:.1}, {d:.1})!",
        .{ actual_c, min_c, max_c },
    ) catch
        std.debug.panic(
            "Temperature body buffer too small for actual: {d}, min: {d}, max: {d}!",
            .{ actual_c, min_c, max_c },
        );

    return ntfyReq(notifier.http_client, .{
        .priority = NtfyPriority.URGENT,
        .base_url = notifier.base_url,
        .auth = notifier.auth,
        .topic = "temperature",
        .title = "Temperature outside range!",
        .body = body,
        .sequence_id = null,
        .offset = null,
    });
}

const NtfyPriority = enum {
    URGENT,
    HIGH,
    DEFAULT,
    LOW,
    MIN,

    fn toHeaderValue(p: NtfyPriority) []const u8 {
        return switch (p) {
            NtfyPriority.URGENT => "urgent",
            NtfyPriority.HIGH => "high",
            NtfyPriority.DEFAULT => "default",
            NtfyPriority.LOW => "low",
            NtfyPriority.MIN => "min",
        };
    }
};

const NtfyParams = struct {
    priority: NtfyPriority,
    base_url: Uri,
    auth: []const u8,
    topic: []const u8,
    title: []const u8,
    body: []const u8,
    sequence_id: ?[]const u8,
    offset: ?Duration,
};

fn toLocation(params: NtfyParams, buf: []u8) Uri {
    return _toLocation(params, buf) catch std.debug.panic("path buffer too small", .{});
}

fn _toLocation(params: NtfyParams, buf: []u8) !Uri {
    var writer: Io.Writer = .fixed(buf);

    try params.base_url.path.formatPath(&writer);
    try writer.writeByte('/');
    try Uri.Component.formatPath(.{ .raw = params.topic }, &writer);
    if (params.sequence_id) |sequence_id| {
        try writer.writeByte('/');
        try Uri.Component.formatPath(.{ .raw = sequence_id }, &writer);
    }

    var url = params.base_url;
    url.path = .{ .percent_encoded = writer.buffered() };

    return url;
}

fn ntfyReq(client: *http.Client, params: NtfyParams) !void {
    var headers_len: u32 = 2;
    var extra_headers = [_]http.Header{
        .{ .name = "Priority", .value = params.priority.toHeaderValue() },
        .{ .name = "Title", .value = params.title },
        undefined,
    };

    var offset_buf: [64]u8 = undefined;
    if (params.offset) |offset| {
        var writer: Io.Writer = .fixed(&offset_buf);
        writer.print("{f}", .{offset}) catch std.debug.panic("offset buffer too small", .{});
        extra_headers[headers_len] = .{
            .name = "In",
            .value = writer.buffered(),
        };
        headers_len += 1;
    }

    var location_buf: [256]u8 = undefined;

    const result = try client.fetch(.{
        .method = http.Method.POST,
        .location = .{ .uri = toLocation(params, &location_buf) },
        .payload = params.body,
        .headers = .{ .authorization = .{ .override = params.auth } },
        .extra_headers = extra_headers[0..headers_len],
    });
    if (result.status.class() != http.Status.Class.success) {
        return error.StatusNotSuccess;
    }
}
