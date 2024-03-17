const std = @import("std");
const tag = @import("builtin").os.tag;
const Mirror = @import("mirror").Mirror;

const log = std.log.scoped(.input);
const fd_t = std.os.fd_t;

pub const Event = union(enum) {
    line: []const u8,
    input: Input,
};

pub const Input = enum {
    Up,
    Down,
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
    src: fd_t,

    mirror: Mirror(0x2000),

    init_read: bool,

    pub fn init(file: ?[]const u8) !Self {
        const user: fd_t = 0;
        var src: fd_t = 0;

        if (file) |f| {
            src = try std.os.open(f, .{
                .ACCMODE = .RDONLY,
                .CLOEXEC = true,
                .NONBLOCK = true,
            }, 0o755);
        } else {
            return InputsError.NoSource;
        }

        const mirror = try Mirror(0x2000).new();

        return Inputs{
            .user = user,
            .src = src,
            .mirror = mirror,
            .init_read = true,
        };
    }

    pub fn load_gen(self: *Self) !?[]const u8 {
        while (true) {
            if (self.mirror.len() != 0) {
                const avail = self.mirror.buffer();
                if (std.mem.indexOf(u8, avail, "\n")) |index| {
                    const line = avail[0..index];

                    _ = self.mirror.drop(index + 1);

                    std.log.debug("line \"{s}\"", .{line});

                    return line;
                }
            }

            const read = try self.mirror.read_fd(self.src);

            if (read == 0) {
                return null;
            }
        }
    }

    pub fn event(self: *Self) !Event {
        while (true) {
            if (self.init_read) {
                const x = self.mirror.read_fd(self.src) catch |err| switch (err) {
                    error.WouldBlock => {
                        self.init_read = false;
                        continue;
                    },

                    else => {
                        return err;
                    },
                };

                if (x == 0) {
                    self.init_read = false;
                }
            }

            if (self.mirror.len() != 0) {
                const avail = self.mirror.buffer();
                if (std.mem.indexOf(u8, avail, "\n")) |index| {
                    const line = avail[0..index];

                    _ = self.mirror.drop(index + 1);

                    std.log.debug("line \"{s}\"", .{line});
                    return Event{ .line = line };
                }
            }

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

                    else => {
                        log.debug("unhandled key {x}", .{ch});
                    },
                }
            }

            if (input) |i| {
                log.debug("event {}", .{i});
                return .{ .input = i };
            }
        }
    }

    pub fn close(self: *Self) void {
        std.os.close(self.user);
        std.os.close(self.src);
    }
};
