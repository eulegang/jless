const std = @import("std");
const tag = @import("builtin").os.tag;

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

    user_ring: std.RingBuffer,
    src_ring: std.RingBuffer,
    allocator: std.mem.Allocator,

    init_read: bool,

    driver: switch (tag) {
        .linux => Epoll,
        .macos => Kqueue,
        else => @compileError("Only suports linux and mac"),
    },

    pub fn init(file: ?[]const u8, allocator: std.mem.Allocator) !Self {
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

        const user_ring = try std.RingBuffer.init(allocator, 128);
        const src_ring = try std.RingBuffer.init(allocator, 4096);

        const driver = switch (tag) {
            .linux => try Epoll.init(user, src),
            .macos => try Kqueue.init(user, src),
            else => @compileError("Only supports mac or linux"),
        };

        return Inputs{
            .user = user,
            .src = src,

            .user_ring = user_ring,
            .src_ring = src_ring,

            .init_read = true,

            .allocator = allocator,

            .driver = driver,
        };
    }

    pub fn event(self: *Self) !Event {
        while (true) {
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
                            'q' => return .{ .input = .Quit },
                            '\x1b' => return .{ .input = .Escape },
                            'j' => return .{ .input = .Down },
                            'k' => return .{ .input = .Up },
                            '\n' => return .{ .input = .Select },

                            else => {
                                std.debug.print("unhandled key {d}\n", .{ch});
                            },
                        }
                    }
                } else if (fd == self.src) {
                    //

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
