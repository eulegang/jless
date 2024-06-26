const std = @import("std");
const ops = @import("ops.zig");

pub usingnamespace @import("term.zig");

const BUF_LEN = 4096;

const SPACE: [BUF_LEN]u8 = .{' '} ** BUF_LEN;

const log = std.log.scoped(.render);

const Err = std.mem.Allocator.Error || std.os.WriteError || error{WindowFetch};

pub const test_instance = switch (@import("builtin").is_test) {
    true => Render{
        .fd = 2,
        .cur = 0,
        .buffer = undefined,
        .window = Window{
            .height = 80,
            .width = 250,
        },
    },

    false => unreachable,
};

const Window = struct {
    width: u16,
    height: u16,

    fn fetch(fd: std.os.fd_t) Err!Window {
        var win: std.os.linux.winsize = undefined;

        if (std.os.linux.ioctl(fd, std.os.linux.T.IOCGWINSZ, @intFromPtr(&win)) == -1) {
            return Err.WindowFetch;
        } else {
            return Window{
                .width = win.ws_col,
                .height = win.ws_row,
            };
        }
    }
};

pub const Render = struct {
    fd: std.os.fd_t,
    cur: usize,
    window: Window,
    buffer: [BUF_LEN]u8,

    pub fn init(fd: std.os.fd_t) Err!Render {
        const window = try Window.fetch(fd);
        var self: Render = Render{
            .fd = fd,
            .cur = 0,
            .buffer = undefined,
            .window = window,
        };

        try self.raw(ops.SAVE_SCREEN);
        try self.raw(ops.ENABLE_ALT);
        try self.raw(ops.CURSOR_INVIS);
        try self.raw(ops.NOAUTOWRAP);
        try self.clear_screen();
        try self.flush();

        return self;
    }

    pub fn deinit(self: *Render) void {
        self.cur = 0;

        self.raw(ops.DISABLE_ALT) catch return;
        self.raw(ops.RESTORE_SCREEN) catch return;
        self.raw(ops.CURSOR_VIS) catch return;
        self.raw(ops.AUTOWRAP) catch return;
        self.flush() catch return;
    }

    fn test_instance() Render {
        return Render{
            .fd = 1,
            .cur = 0,
            .buffer = undefined,
            .window = Window{
                .height = 80,
                .width = 250,
            },
        };
    }

    pub fn flush(self: *Render) Err!void {
        var written: usize = 0;
        while (written < self.cur) {
            written += try std.os.write(self.fd, self.buffer[written..self.cur]);
        }

        self.cur = 0;
    }

    pub fn raw(self: *Render, cmd: []const u8) Err!void {
        if (cmd.len + self.cur >= BUF_LEN) {
            return std.mem.Allocator.Error.OutOfMemory;
        }

        std.mem.copyForwards(u8, self.buffer[self.cur..], cmd);
        self.cur += cmd.len;
    }

    pub fn blanks(self: *Render, amount: usize) Err!void {
        try self.raw(SPACE[0..amount]);
    }

    pub fn push_line(self: *Render, content: []const u8) Err!void {
        const len = @min(content.len, self.window.width);
        const pad = self.window.width - len;

        try self.raw(content[0..len]);
        try self.raw(SPACE[0..pad]);
    }

    pub fn push_phantom_pad(self: *Render, content: []const u8) Err!void {
        const len = @min(content.len, self.window.width);
        const pad = self.window.width - len;
        try self.raw(SPACE[0..pad]);
    }

    pub fn render(self: *Render, op: anytype) Err!void {
        try op.render(self);
    }

    pub fn clear_screen(self: *Render) Err!void {
        try self.raw("\x1b[2J");
    }

    pub fn move_cursor(self: *Render, line: u16, col: u16) Err!void {
        try self.fmt("\x1b[{};{}H", .{ line + 1, col });
    }

    pub fn fmt(self: *Render, comptime format: []const u8, args: anytype) Err!void {
        const sub = std.fmt.bufPrint(self.buffer[self.cur..], format, args) catch return Err.OutOfMemory;
        self.cur += sub.len;
    }
};
