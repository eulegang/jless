const std = @import("std");
const tag = @import("builtin").os.tag;
const Mirror = @import("mirror").Mirror;

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

    driver: switch (tag) {
        .linux => Epoll,
        .macos => Kqueue,
        else => @compileError("Only suports linux and mac"),
    },

    pub fn init(file: ?[]const u8) !Self {
        var user: fd_t = 0;
        var src: fd_t = 0;

        if (file) |f| {
            src = try std.os.open(f, .{
                .ACCMODE = .RDONLY,
                .CLOEXEC = true,
                .NONBLOCK = true,
            }, 0o755);

            try set_nonblocking(user);
        } else {
            if (std.os.isatty(src)) {
                return InputsError.NoSource;
            }

            try set_nonblocking(src);
            user = try std.os.open("/dev/tty", .{
                .ACCMODE = .RDONLY,
                .CLOEXEC = true,
                .NONBLOCK = true,
            }, 0o755);
        }

        const mirror = try Mirror(0x2000).new();

        const driver = switch (tag) {
            .linux => try Epoll.init(user, src),
            .macos => try Kqueue.init(user, src),
            else => @compileError("Only supports mac or linux"),
        };

        return Inputs{
            .user = user,
            .src = src,

            .mirror = mirror,

            .init_read = true,

            .driver = driver,
        };
    }

    pub fn event(self: *Self) !Event {
        while (true) {
            // TODO: something seems wrong here
            if (self.init_read) {
                _ = self.mirror.read_fd(self.src) catch |err| switch (err) {
                    error.WouldBlock => {
                        self.init_read = false;
                    },

                    else => {
                        return err;
                    },
                };
            }

            if (self.mirror.len() != 0) {
                const avail = self.mirror.buffer();
                if (std.mem.indexOf(u8, avail, "\n")) |index| {
                    const line = avail[0..index];

                    _ = self.mirror.drop(index + 1);

                    return Event{ .line = line };
                }
            }

            if (try self.driver.next()) |fd| {
                std.debug.print("what? {d} ({}, {})\r\n", .{ fd, self.user, self.src });
                if (fd == self.user) {
                    std.debug.print("reading? {d}\r\n", .{self.user});
                    var buf: [4]u8 = undefined;
                    const len = try std.os.read(fd, &buf);

                    if (len == 0) continue;

                    const ch = buf[0];

                    if (len == 1) {
                        switch (ch) {
                            '\x1b' => return .{ .input = .Escape },
                            '\n' => return .{ .input = .Select },

                            'q' => return .{ .input = .Quit },
                            'j' => return .{ .input = .Down },
                            'k' => return .{ .input = .Up },

                            else => {
                                std.debug.print("unhandled key {d}\r\n", .{ch});
                            },
                        }
                    }
                } else if (fd == self.src) {
                    _ = self.mirror.read_fd(self.src) catch |err| switch (err) {
                        error.WouldBlock => continue,
                        else => return err,
                    };

                    const avail = self.mirror.buffer();

                    if (std.mem.indexOf(u8, avail, "\n")) |index| {
                        const line = avail[0..index];

                        _ = self.mirror.drop(index + 1);

                        return Event{ .line = line };
                    }
                } else {
                    unreachable;
                }
            }
        }
    }

    pub fn close(self: *Self) void {
        std.os.close(self.user);
        std.os.close(self.src);
    }
};

const WatcherError = error{watcher_create_error};

const epoll_t = @import("inputs/epoll.zig").epoll_t;
const Epoll = struct {
    user: fd_t,
    src: fd_t,

    epoll: epoll_t,

    fn init(user: fd_t, src: fd_t) !@This() {
        const epoll = try epoll_t.init();

        try epoll.add(user);
        try epoll.add(src);

        return @This(){
            .user = user,
            .src = src,
            .epoll = epoll,
        };
    }

    fn next(self: @This()) !?fd_t {
        return self.epoll.next();
    }

    fn deinit(self: @This()) void {
        self.epoll.deinit();
    }
};

const Kqueue = struct {
    fn init() @This() {
        return @This(){};
    }
};

fn set_nonblocking(fd: fd_t) !void {
    const NONBLOCK = 1 << @bitOffsetOf(std.os.system.O, "NONBLOCK");
    const flags = try std.os.fcntl(fd, std.os.F.GETFL, 0);
    _ = try std.os.fcntl(fd, std.os.F.SETFL, flags | NONBLOCK);
}
