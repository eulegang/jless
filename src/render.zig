const std = @import("std");

const BUF_LEN = 512;
const RESTORE_SCREEN = "\x1b[?47l";
const SAVE_SCREEN = "\x1b[?47h";

const ENABLE_ALT = "\x1b[?1049h";
const DISABLE_ALT = "\x1b[?1049h";

const CURSOR_VIS = "\x1b[?25h";
const CURSOR_INVIS = "\x1b[?25l";

const SPACE: [512]u8 = .{' '} ** 512;

const Err = std.mem.Allocator.Error || std.os.WriteError || error{WindowFetch};

const Color = enum(u8) {
    Black = 0,
    Red = 1,
    Green = 2,
    Yellow = 3,
    Blue = 4,
    Magenta = 5,
    Cyan = 6,
    White = 7,
    Default = 9,

    fn byte(self: Color) u8 {
        return '0' + @intFromEnum(self);
    }
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

        try self.push(SAVE_SCREEN);
        try self.push(ENABLE_ALT);
        try self.push(CURSOR_INVIS);
        try self.clear_screen();
        try self.flush();

        return self;
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

    fn push(self: *Render, cmd: []const u8) Err!void {
        if (cmd.len + self.cur >= BUF_LEN) {
            return std.mem.Allocator.Error.OutOfMemory;
        }

        std.mem.copyForwards(u8, self.buffer[self.cur..], cmd);
        self.cur += cmd.len;
    }

    pub fn push_line(self: *Render, content: []const u8) Err!void {
        const len = @min(content.len, self.window.width);
        const pad = self.window.width - len;

        try self.push(content[0..len]);
        try self.push(SPACE[0..pad]);
    }

    pub fn clear_screen(self: *Render) Err!void {
        try self.push("\x1b[2J");
    }

    pub fn move_cursor(self: *Render, line: u16, col: u16) Err!void {
        try self.pushf("\x1b[{};{}H", .{ line + 1, col + 1 });
    }

    pub fn fg(self: *Render, color: Color) Err!void {
        try self.pushf("\x1b[3{c}m", .{color.byte()});
    }

    pub fn true_fg(self: *Render, color: u32) Err!void {
        const red = (color >> 16) & 0xFF;
        const green = (color >> 8) & 0xFF;
        const blue = color & 0xFF;
        try self.pushf("\x1b[38;2;{};{};{}m", .{ red, green, blue });
    }

    pub fn bg(self: *Render, color: Color) Err!void {
        try self.pushf("\x1b[4{c}m", .{color.byte()});
    }

    pub fn true_bg(self: *Render, color: u32) Err!void {
        const red = (color >> 16) & 0xFF;
        const green = (color >> 8) & 0xFF;
        const blue = color & 0xFF;
        try self.pushf("\x1b[48;2;{};{};{}m", .{ red, green, blue });
    }

    pub fn pushf(self: *Render, comptime fmt: []const u8, args: anytype) Err!void {
        const sub = std.fmt.bufPrint(self.buffer[self.cur..], fmt, args) catch return Err.OutOfMemory;
        self.cur += sub.len;
    }

    pub fn deinit(self: *Render) void {
        self.cur = 0;

        self.push(DISABLE_ALT) catch return;
        self.push(RESTORE_SCREEN) catch return;
        self.push(CURSOR_VIS) catch return;
        self.flush() catch return;
    }
};

test "set colors" {
    var render = Render.test_instance();

    try render.bg(.Black);
    try render.fg(.Green);

    try std.testing.expectEqualSlices(u8, "\x1b[40m\x1b[32m", render.buffer[0..render.cur]);
}

test "set true colors" {
    var render = Render.test_instance();

    try render.true_bg(0x00_aa_ff);
    try render.true_fg(0xff_bb_11);

    try std.testing.expectEqualSlices(u8, "\x1b[48;2;0;170;255m\x1b[38;2;255;187;17m", render.buffer[0..render.cur]);
}

test "moving cursor" {
    var render = Render.test_instance();

    try render.move_cursor(0, 0);
    try render.move_cursor(10, 10);

    try std.testing.expectEqualSlices(u8, "\x1b[1;1H\x1b[11;11H", render.buffer[0..render.cur]);
}
