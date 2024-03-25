const std = @import("std");

pub const Report = enum {
    Failed,
    Success,
};

const Obj: u1 = 1;
const Arr: u1 = 1;

pub const JsonP = struct {
    stack: std.BitStack,
    str: bool,
    escape: bool,

    pub fn init(alloc: std.mem.Allocator) !*JsonP {
        var self = try alloc.create(JsonP);
        errdefer alloc.destroy(self);

        self.stack = std.BitStack.init(alloc);

        self.str = false;
        self.escape = false;
        return self;
    }

    pub fn deinit(self: *JsonP, alloc: std.mem.Allocator) void {
        self.stack.deinit();
        alloc.destroy(self);
    }

    fn reset(self: *JsonP) void {
        self.stack.bit_len = 0;
        self.stack.bytes.clearRetainingCapacity();
        self.str = false;
        self.escape = false;
    }

    pub fn visit(self: *JsonP, ch: u8) !?Report {
        switch (ch) {
            '{' => try self.stack.push(Obj),
            '}' => {
                if (self.stack.bit_len == 0) {
                    return .Failed;
                }

                const s = self.stack.pop();
                if (s != Obj) {
                    return .Failed;
                }
            },

            '[' => try self.stack.push(Arr),
            '\n' => {
                if (self.stack.bit_len == 0) {
                    return .Success;
                } else {
                    return .Failed;
                }
            },

            else => {},
        }

        return null;
    }
};

const overrun = error{
    overrun,
};

fn test_jsonp(buf: []const u8, json: *JsonP, report: Report) !void {
    for (buf) |ch| {
        if (try json.visit(ch)) |r| {
            errdefer std.debug.print("jsonp {}", .{json});

            try std.testing.expectEqual(report, r);

            return;
        }
    }

    return overrun.overrun;
}

test "jsonp visit" {
    const json = try JsonP.init(std.testing.allocator);
    defer json.deinit(std.testing.allocator);

    try test_jsonp("{\n", json, .Failed);
    json.reset();

    try test_jsonp("{}\n", json, .Success);
    json.reset();
}
