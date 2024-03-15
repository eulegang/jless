const std = @import("std");
const cli = @import("zig-cli");
const xyz = @import("jq.zig");

const System = @import("system.zig").System;

const jq = @cImport({
    @cInclude("jq.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var args = struct {
    expr: []const u8 = "",
    file: ?[]const u8 = null,
}{};

var file = cli.Option{
    .short_alias = 'f',
    .long_name = "file",
    .help = "",
    .value_ref = cli.mkRef(&args.file),
};

var app = &cli.App{ .command = cli.Command{
    .name = "jless",
    .options = &.{&file},
    .target = cli.CommandTarget{
        .action = cli.CommandAction{ .exec = run },
    },
} };

pub fn main() !void {
    return cli.run(app, allocator);
}

pub fn run() !void {
    var system = try System.init(args.file);
    defer system.close();

    try system.setup();

    while (try system.tick()) {}
}
