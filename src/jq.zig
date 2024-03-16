const std = @import("std");
const c = @cImport({
    @cInclude("jq.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const JQ = struct {
    const err = error{ failed_init, failed_compile };

    st: *c.jq_state,
    prog: [*c]const u8,

    pub fn init(program: []const u8) !JQ {
        if (c.jq_init()) |st| {
            c.jq_set_error_cb(st, &err_report, null);
            const prog = try allocator.dupeZ(u8, program);

            if (c.jq_compile(st, prog) == 0) {
                return err.failed_compile;
            }
            return JQ{ .st = st, .prog = prog };
        } else {
            return err.failed_init;
        }
    }

    pub fn deinit(self: JQ) void {
        c.jq_teardown(&self.st);
        allocator.free(self.prog);
    }
};

fn err_report(_: ?*anyopaque, value: c.jv) callconv(.C) void {
    var buf: [256]u8 = undefined;

    _ = c.jv_dump_string_trunc(value, &buf, 256);

    std.debug.print("\x1b[31m{s}\x1b[0m\n", .{buf});
}
