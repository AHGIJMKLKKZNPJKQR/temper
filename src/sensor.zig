const std = @import("std");
const config = @import("config.zig");

const Io = std.Io;
const Dir = Io.Dir;
const File = Io.File;
const Config = config.Config;

pub fn readTemperatureMilliCelsius(sensor: Io.File, io: Io) !i32 {
    var buf: [32]u8 = undefined;
    const len = try sensor.readPositionalAll(io, &buf, 0);
    std.debug.assert(len < buf.len);
    return std.fmt.parseInt(i32, buf[0..len], 10);
}

pub fn setupSensor(cfg: Config, io: Io) !File {
    try setupFeatures(cfg, io);
    return openTemperatureFile(cfg, io);
}

fn setupFeatures(cfg: Config, io: Io) !void {
    const features_file = try Dir.openFile(cfg.sensor_directory, io, "features", .{ .mode = .write_only });
    defer features_file.close(io);

    try features_file.writePositionalAll(io, "1", 0);
}

fn openTemperatureFile(cfg: Config, io: Io) !File {
    return Dir.openFile(cfg.sensor_directory, io, "temperature", .{ .mode = .read_only });
}
