const std = @import("std");
const tag = @import("builtin").os.tag;
const Mirror = @import("mirror").Mirror;

const log = std.log.scoped(.input);
const fd_t = std.os.fd_t;

pub const Input = union(InputMode) {
    list: ListInput,
    insert: InsertInput,
};

pub const InputMode = enum {
    list,
    insert,
};

pub const ListInput = enum {
    Up,
    Down,

    Begin,
    End,

    HalfPageUp,
    HalfPageDown,

    FullPageUp,
    FullPageDown,

    OpenFilter,
    OpenProjection,

    Select,
    Quit,
    Escape,

    fn process(buf: []const u8) ?@This() {
        if (buf.len == 1) {
            switch (buf[0]) {
                '\x1b' => return .Escape,
                '\n' => return .Select,

                'q' => return .Quit,
                'j' => return .Down,
                'k' => return .Up,

                'd' => return .HalfPageDown,
                'u' => return .HalfPageUp,

                'f' => return .FullPageDown,
                'b' => return .FullPageUp,

                'p' => return .OpenProjection,
                'o' => return .OpenFilter,

                'g' => return .Begin,
                'G' => return .End,

                else => {},
            }
        }

        return null;
    }
};

pub const InsertInput = union(enum) {
    Escape: void,
    Cancel: void,
    Submit: void,
    BS: void,
    Raw: u8,

    fn process(buf: []const u8) ?@This() {
        if (buf.len == 1) {
            switch (buf[0]) {
                '\n' => return .Submit,
                '\x1b' => return .Escape,
                127, 8 => return .BS,
                3 => return .Cancel,

                else => {
                    return .{ .Raw = buf[0] };
                },
            }
        }

        return null;
    }
};

pub const InputsError = error{
    NoSource,
};

pub const Inputs = struct {
    const Self = @This();

    user: fd_t,
    mode: InputMode,

    pub fn init() !Self {
        return Inputs{
            .user = 0,
            .mode = InputMode.list,
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

            log.debug("input", .{ .mode = self.mode, .len = len, .buf = buf[0..len] });

            switch (self.mode) {
                .list => {
                    if (ListInput.process(buf[0..len])) |input| {
                        return .{ .list = input };
                    }
                },
                .insert => {
                    if (InsertInput.process(buf[0..len])) |input| {
                        return .{ .insert = input };
                    }
                },
            }
        }
    }
};
