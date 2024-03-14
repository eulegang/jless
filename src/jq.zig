const std = @import("std");
const c = @cImport({
    @cInclude("jq.h");
});

pub const JQ = struct {
    st: *c.jq_state,

    fn new() JQ {
        const st = c.jq_init();
        c.jq_set_error_cb(st, &err_report, null);

        return JQ{ .st = st };
    }
};

fn err_report(_: ?*anyopaque, value: c.jv) callconv(.C) void {
    var buf: [256]u8 = undefined;

    _ = c.jv_dump_string_trunc(value, &buf, 256);

    std.debug.print("\x1b[31m{s}\x1b[0m\n", .{buf});
}
