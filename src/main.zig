const std = @import("std");
const cli = @import("zig-cli");

const jq = @cImport({
    @cInclude("jq.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

var st: ?*jq.jq_state = null;

var config = struct {
    expr: []const u8 = "",
}{};

var expr = cli.Option{
    .short_alias = 'e',
    .long_name = "expr",
    .help = "jq expression",
    .value_ref = cli.mkRef(&config.expr),
};

var app = &cli.App{ .command = cli.Command{
    .name = "jless",
    .options = &.{&expr},
    .target = cli.CommandTarget{
        .action = cli.CommandAction{ .exec = run },
    },
} };

pub fn main() !void {
    return cli.run(app, allocator);
}

pub fn run() !void {
    const state = jq.jq_init();
    jq.jq_set_error_cb(state, &err_report, null);

    const e = try allocator.dupeZ(u8, config.expr);
    defer allocator.free(e);

    const sucess = jq.jq_compile(state, e);

    if (sucess != 0) {} else {
        _ = try std.io.getStdErr().write("\x1b[31mfailed to compile jq expression\x1b[0m\n");
        return;
    }
}

fn err_report(_: ?*anyopaque, value: jq.jv) callconv(.C) void {
    var buf: [256]u8 = undefined;

    _ = jq.jv_dump_string_trunc(value, &buf, 256);

    std.debug.print("\x1b[31m{s}\x1b[0m\n", .{buf});
    //std.io.getStdErr().write("\x1b[31mError from jq \"{s}"
}
