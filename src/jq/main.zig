const std = @import("std");
const c = @cImport({
    @cInclude("jq.h");
});

const Err = std.mem.Allocator.Error || error{
    failed_init,
    failed_compile,
    failed_parser_init,
};

pub const JQ = struct {
    st: *c.jq_state,
    parser: *c.jv_parser,
    prog: [:0]const u8,
    allocator: std.mem.Allocator,
    buffer: []u8,

    pub fn init(program: []const u8, allocator: std.mem.Allocator) Err!*JQ {
        var jq = try allocator.create(JQ);
        errdefer allocator.destroy(jq);

        jq.st = c.jq_init() orelse return Err.failed_compile;

        const prog = try allocator.dupeZ(u8, program);
        errdefer allocator.free(prog);

        jq.prog = prog;

        if (c.jq_compile(jq.st, prog) == 0) {
            return Err.failed_compile;
        }

        jq.parser = c.jv_parser_new(0) orelse return Err.failed_parser_init;

        jq.buffer = try allocator.alloc(u8, 0x2000);
        jq.allocator = allocator;

        return jq;
    }

    pub fn deinit(self: *JQ) void {
        c.jq_teardown(@constCast(@ptrCast(&self.st)));
        c.jv_parser_free(self.parser);
        self.allocator.free(self.buffer);
        self.allocator.free(self.prog);
        self.allocator.destroy(self);
    }

    pub fn project(self: *const JQ, line: []const u8) Err![]const u8 {
        c.jv_parser_set_buf(self.parser, line.ptr, @intCast(line.len), 0);

        const jv = c.jv_parser_next(self.parser);

        c.jq_start(self.st, jv, 0);

        const out = c.jq_next(self.st);

        const repr = c.jv_dump_string_trunc(out, self.buffer.ptr, @intCast(self.buffer.len));
        return std.mem.span(repr);
    }

    pub fn predicate(self: *const JQ, line: []const u8) Err!bool {
        c.jv_parser_set_buf(self.parser, line.ptr, @intCast(line.len), 0);

        const jv = c.jv_parser_next(self.parser);

        c.jq_start(self.st, jv, 0);

        const out = c.jq_next(self.st);

        const kind = c.jv_get_kind(out);

        return switch (kind) {
            c.JV_KIND_TRUE => true,
            c.JV_KIND_NULL, c.JV_KIND_FALSE => false,

            else => false,
        };
    }
};
