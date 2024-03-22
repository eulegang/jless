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
            .bg = .{ .true = .{ .red = 0x33, .green = 0xAA, .blue = 0x33 } },
            .fg = .{ .true = .{ .red = 0x24, .green = 0x28, .blue = 0x3b } },
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

    fn parse(repr: []const u8) ?Color {
        if (repr.len == 7 and repr[0] == '#') {
            var valid = true;
            for (repr[1..]) |ch| {
                valid = valid and std.ascii.isHex(ch);
            }

            if (!valid) {
                return null;
            }

            const res = Color{
                .true = .{
                    .red = hex(repr[1], repr[2]),
                    .green = hex(repr[3], repr[4]),
                    .blue = hex(repr[5], repr[6]),
                },
            };

            return res;
        } else if (repr.len > 0) {
            switch (repr[0]) {
                'b', 'B' => {
                    if (std.ascii.eqlIgnoreCase(repr, "blue")) {
                        return .{ .basic = .Blue };
                    }
                    if (std.ascii.eqlIgnoreCase(repr, "black")) {
                        return .{ .basic = .Black };
                    }
                },

                'r', 'R' => {
                    if (std.ascii.eqlIgnoreCase(repr, "red")) {
                        return .{ .basic = .Red };
                    }
                },

                'g', 'G' => {
                    if (std.ascii.eqlIgnoreCase(repr, "green")) {
                        return .{ .basic = .Green };
                    }
                },

                'y', 'Y' => {
                    if (std.ascii.eqlIgnoreCase(repr, "yellow")) {
                        return .{ .basic = .Yellow };
                    }
                },

                'm', 'M', 'p', 'P' => {
                    if (std.ascii.eqlIgnoreCase(repr, "magenta")) {
                        return .{ .basic = .Magenta };
                    }

                    if (std.ascii.eqlIgnoreCase(repr, "purple")) {
                        return .{ .basic = .Magenta };
                    }
                },

                'c', 'C' => {
                    if (std.ascii.eqlIgnoreCase(repr, "cyan")) {
                        return .{ .basic = .Cyan };
                    }
                },

                'w', 'W' => {
                    if (std.ascii.eqlIgnoreCase(repr, "white")) {
                        return .{ .basic = .White };
                    }
                },

                'd', 'D' => {
                    if (std.ascii.eqlIgnoreCase(repr, "default")) {
                        return .{ .basic = .Default };
                    }
                },

                else => {},
            }
        }

        return null;
    }
};

fn hex(hi: u8, lo: u8) u8 {
    const low: u8 = switch (lo) {
        '0'...'9' => lo - '0',
        'a'...'f' => lo - 'a' + 10,
        'A'...'F' => lo - 'A' + 10,
        else => unreachable,
    };

    const high: u8 = switch (hi) {
        '0'...'9' => hi - '0',
        'a'...'f' => hi - 'a' + 10,
        'A'...'F' => hi - 'A' + 10,
        else => unreachable,
    };

    var res = low;
    res |= @shlExact(high, 4);
    return res;
}

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

test "parse color" {
    try std.testing.expectEqual(Color{ .basic = BasicColor.Black }, Color.parse("Black"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Red }, Color.parse("Red"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Green }, Color.parse("Green"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Yellow }, Color.parse("Yellow"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Blue }, Color.parse("Blue"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Magenta }, Color.parse("Magenta"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Magenta }, Color.parse("Purple"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Cyan }, Color.parse("Cyan"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.White }, Color.parse("White"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Default }, Color.parse("Default"));

    try std.testing.expectEqual(Color{ .basic = BasicColor.Black }, Color.parse("black"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Red }, Color.parse("red"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Green }, Color.parse("green"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Yellow }, Color.parse("yellow"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Blue }, Color.parse("blue"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Magenta }, Color.parse("magenta"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Magenta }, Color.parse("purple"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Cyan }, Color.parse("cyan"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.White }, Color.parse("white"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Default }, Color.parse("default"));

    try std.testing.expectEqual(Color{ .basic = BasicColor.Black }, Color.parse("BLACK"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Red }, Color.parse("RED"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Green }, Color.parse("GREEN"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Yellow }, Color.parse("YELLOW"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Blue }, Color.parse("BLUE"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Magenta }, Color.parse("MAGENTA"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Magenta }, Color.parse("PURPLE"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Cyan }, Color.parse("CYAN"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.White }, Color.parse("WHITE"));
    try std.testing.expectEqual(Color{ .basic = BasicColor.Default }, Color.parse("DEFAULT"));

    try std.testing.expectEqual(null, Color.parse("pink"));

    try std.testing.expectEqual(Color{ .true = .{ .red = 0, .green = 0, .blue = 0 } }, Color.parse("#000000"));
    try std.testing.expectEqual(Color{ .true = .{ .red = 255, .green = 255, .blue = 255 } }, Color.parse("#FFFFFF"));
    try std.testing.expectEqual(Color{ .true = .{ .red = 255, .green = 0, .blue = 0 } }, Color.parse("#FF0000"));
    try std.testing.expectEqual(Color{ .true = .{ .red = 0, .green = 255, .blue = 0 } }, Color.parse("#00FF00"));
    try std.testing.expectEqual(Color{ .true = .{ .red = 0, .green = 0, .blue = 255 } }, Color.parse("#0000FF"));
    try std.testing.expectEqual(Color{ .true = .{ .red = 0xA0, .green = 0, .blue = 0x0A } }, Color.parse("#A0000A"));

    try std.testing.expectEqual(null, Color.parse("#A0000AA"));
    try std.testing.expectEqual(null, Color.parse("#A0000"));
}
