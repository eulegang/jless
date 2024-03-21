const std = @import("std");
const cli = @import("zig-cli");
const JQ = @import("jq.zig").JQ;

const System = @import("system.zig").System;

const theme = @import("theme.zig");

pub const std_options = .{
    // Set the log level to info
    .log_level = std.log.Level.debug,

    // Define logFn to override the std implementation
    .logFn = @import("log.zig").jsonLog,
};

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
    .value_ref = cli.mkRef(&args.projection),
};

var app = &cli.App{ .command = cli.Command{
    .name = "jless",
    .options = &.{ &file_opt, &projection_opt },
    .target = cli.CommandTarget{
        .action = cli.CommandAction{ .exec = run },
    },
} };

pub fn main() !void {
    return cli.run(app, allocator);
}

pub fn run() !void {
    var env = try std.process.getEnvMap(allocator);

    var system = try System.init(args.file, allocator);
    defer system.close();

    if (args.filter) |f| {
        system.filter = try JQ.init(f, allocator);
    }

    defer {
        if (system.filter) |f| {
            f.deinit();
        }
    }

    if (args.projection) |p| {
        std.debug.print("hello? {s}\n", .{p});
        system.projection = try JQ.init(p, allocator);
        std.debug.print("worked\n", .{});
    }

    defer {
        if (system.projection) |p| {
            p.deinit();
        }
    }

    if (env.get("JLESS_THEME")) |theme_env| {
        if (theme.Theme.parse(theme_env)) |t| {
            system.theme = t;
        } else {
            return MainError.invalid_theme;
        }
    }

    try system.setup();

    while (try system.tick()) {}
}

const MainError = error{
    invalid_theme,
};
