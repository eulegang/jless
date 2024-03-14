const std = @import("std");

const fd_t = std.os.fd_t;
const linux = std.os.linux;

const epoll_error = error{
    init,
    add,
    next,
};

pub const epoll_t = struct {
    fd: fd_t,

    pub fn init() !epoll_t {
        const res = linux.epoll_create();

        if (res < 0) {
            return epoll_error.init;
        }

        const fd: fd_t = @intCast(res);

        return epoll_t{ .fd = fd };
    }

    pub fn add(self: epoll_t, fd: fd_t) !void {
        var ev: linux.epoll_event = undefined;
        ev.events = linux.EPOLL.IN;
        ev.data = .{ .fd = @as(i32, fd) };

        const res = linux.epoll_ctl(self.fd, linux.EPOLL.CTL_ADD, fd, &ev);

        if (res == -1) {
            return epoll_error.add;
        }
    }

    pub fn next(self: epoll_t) !?fd_t {
        var events: [2]linux.epoll_event = undefined;
        const res = linux.epoll_wait(self.fd, &events, 2, -1);

        if (res < 0) {
            return epoll_error.next;
        }

        if (res == 0) {
            return null;
        }

        const event = events[0];
        return event.data.fd;
    }

    pub fn deinit(self: epoll_t) void {
        std.os.close(self.fd);
    }
};
