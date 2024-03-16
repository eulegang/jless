const std = @import("std");
const cli = @import("zig-cli");
const JQ = @import("jq.zig").JQ;

const System = @import("system.zig").System;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var args = struct {
    expr: []const u8 = "",
    file: ?[]const u8 = null,
    filter: ?[]const u8 = null,
    projection: ?[]const u8 = null,
}{};

var file_opt = cli.Option{
    .short_alias = 'f',
    .long_name = "file",
    .help = "file to look through",
    .value_ref = cli.mkRef(&args.file),
};

var filter_opt = cli.Option{
    .short_alias = 'F',
    .long_name = "filter",
    .help = "jq filter",
    .value_ref = cli.mkRef(&args.filter),
};

var projection_opt = cli.Option{
    .short_alias = 'p',
    .long_name = "project",
    .help = "jq projection",
    .value_ref = cli.mkRef(&args.filter),
};

var app = &cli.App{ .command = cli.Command{
    .name = "jless",
    .options = &.{ &file_opt, &filter_opt },
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

    if (args.filter) |f| {
        system.filter = try JQ.init(f);
    }

    if (args.projection) |p| {
        system.projection = try JQ.init(p);
    }

    try system.setup();

    while (try system.tick()) {}
}
