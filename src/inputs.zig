const std = @import("std");
const tag = @import("builtin").os.tag;
const Mirror = @import("mirror").Mirror;

const log = std.log.scoped(.input);
const fd_t = std.os.fd_t;

pub const Input = enum {
    Up,
    Down,

    Begin,
    End,

    HalfPageUp,
    HalfPageDown,

    FullPageUp,
    FullPageDown,

    Select,
    Quit,
    Escape,
};

pub const InputsError = error{
    NoSource,
};

pub const Inputs = struct {
    const Self = @This();

    user: fd_t,

    pub fn init() !Self {
        return Inputs{
            .user = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        std.os.close(self.user);
    }

    pub fn event(self: *Self) !Input {
        while (true) {
            var buf: [4]u8 = undefined;
            const len = try std.os.read(self.user, &buf);

            if (len == 0) continue;

            const ch = buf[0];

            var input: ?Input = null;

            if (len == 1) {
                switch (ch) {
                    '\x1b' => input = .Escape,
                    '\n' => input = .Select,

                    'q' => input = .Quit,
                    'j' => input = .Down,
                    'k' => input = .Up,

                    'd' => input = .HalfPageDown,
                    'u' => input = .HalfPageUp,

                    'f' => input = .FullPageDown,
                    'b' => input = .FullPageUp,

                    'g' => input = .Begin,
                    'G' => input = .End,

                    else => {
                        log.debug("unhandled key {x}", .{ch});
                    },
                }
            }

            if (input) |i| {
                log.debug("event {}", .{i});
                return i;
            }
        }
    }
};
