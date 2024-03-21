const std = @import("std");

const render = @import("render.zig");
const Render = render.Render;

pub const Theme = struct {
    selected: ColorPair,
    default: ColorPair,

    pub const DEFAULT = .{
        .default = .{
            .fg = .{ .true = .{ .red = 0x73, .green = 0x7A, .blue = 0xA2 } },
            .bg = .{ .true = .{ .red = 0x24, .green = 0x28, .blue = 0x3b } },
        },
        .selected = .{
            .fg = .{ .true = .{ .red = 0x33, .green = 0xAA, .blue = 0x33 } },
            .bg = .{ .true = .{ .red = 0x34, .green = 0xe8, .blue = 0x4A } },
        },
    };
};

pub const ColorPair = struct {
    fg: Color,
    bg: Color,

    pub fn render(self: @This(), r: *Render) !void {
        switch (self.fg) {
            .true => |c| {
                try r.fmt("\x1b[38;2;{};{};{}m", .{ c.red, c.green, c.blue });
            },

            .basic => |c| {
                try r.fmt("\x1b[3{c}m", .{@intFromEnum(c)});
            },
        }

        switch (self.bg) {
            .true => |c| {
                try r.fmt("\x1b[48;2;{};{};{}m", .{ c.red, c.green, c.blue });
            },

            .basic => |c| {
                try r.fmt("\x1b[4{c}m", .{@intFromEnum(c)});
            },
        }
    }
};

pub const Color = union(enum) {
    basic: BasicColor,
    true: TrueColor,
};

pub const BasicColor = enum(u8) {
    Black = '0',
    Red = '1',
    Green = '2',
    Yellow = '3',
    Blue = '4',
    Magenta = '5',
    Cyan = '6',
    White = '7',
    Default = '9',
};

pub const TrueColor = packed struct {
    red: u8 = 0,
    green: u8 = 0,
    blue: u8 = 0,

    comptime {
        std.debug.assert(@sizeOf(@This()) == @sizeOf(u32));
        std.debug.assert(@bitSizeOf(@This()) == @bitSizeOf(u24));
        //std.debug.assert(@bitSizeOf(@This()) == @bitSizeOf(u32));
    }
};

test "set colors" {
    var r = render.test_instance;

    try r.render(ColorPair{
        .fg = .{ .basic = .Green },
        .bg = .{ .basic = .Black },
    });

    try std.testing.expectEqualSlices(u8, "\x1b[32m\x1b[40m", r.buffer[0..r.cur]);
}

test "set true colors" {
    var r = render.test_instance;

    try r.render(ColorPair{
        .fg = .{ .true = .{ .red = 0xff, .green = 0xbb, .blue = 0x11 } },
        .bg = .{ .true = .{ .red = 0x00, .green = 0xaa, .blue = 0xff } },
    });

    try std.testing.expectEqualSlices(u8, "\x1b[38;2;255;187;17m\x1b[48;2;0;170;255m", r.buffer[0..r.cur]);
}
