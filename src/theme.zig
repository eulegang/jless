const std = @import("std");

const render = @import("render");
const Render = render.Render;

const log = std.log.scoped(.theme);

pub const Syntax = struct {
    json: struct {
        string: Color,
        key: Color,
        number: Color,
        punct: Color,
        bool: Color,
        null: Color,
    },

    jq: struct {
        string: Color,
        key: Color,
        number: Color,
        boolean: Color,
        null: Color,
        keyword: Color,
        operator: Color,
        builtin: Color,
        punct: Color,
        delim: Color,
        comment: Color,
    },
};

pub const Theme = struct {
    selected: ColorPair,
    default: ColorPair,

    syntax: Syntax,

    filter: struct {
        success: Color,
        fail: Color,
    },

    pub const DEFAULT = Theme{
        .default = .{
            .fg = Color.parse("#737AA2").?,
            .bg = Color.parse("#24283B").?,
        },
        .selected = .{
            .fg = Color.parse("#24283b").?,
            .bg = Color.parse("#33AA33").?,
        },
        .filter = .{
            .success = Color.parse("#24E83B").?,
            .fail = Color.parse("#E4283B").?,
        },
        .syntax = .{
            .json = .{
                .string = Color.parse("#24D6D6").?,
                .key = Color.parse("#73D6A2").?,
                .number = Color.parse("#737AD6").?,
                .punct = Color.parse("#D6D6A2").?,
                .bool = Color.parse("#73D6D6").?,
                .null = Color.parse("#73D6D6").?,
            },

            .jq = .{
                .string = Color.parse("#24D6D6").?,
                .key = Color.parse("#73D6A2").?,
                .number = Color.parse("#737AD6").?,
                .punct = Color.parse("#D6D6A2").?,
                .boolean = Color.parse("#73D6D6").?,
                .null = Color.parse("#73D6D6").?,

                .keyword = Color.parse("#73D6A2").?,
                .operator = Color.parse("#73D6D6").?,
                .builtin = Color.parse("#73D6A2").?,
                .delim = Color.parse("#73D6A2").?,
                .comment = Color.parse("#34383B").?,
            },
        },
    };

    pub fn parse(repr: []const u8) ?Theme {
        var iter = std.mem.splitScalar(u8, repr, ';');

        var theme = Theme.DEFAULT;

        while (iter.next()) |part| {
            if (part.len == 0) {
                continue;
            }

            if (std.mem.indexOfScalar(u8, part, '=')) |i| {
                const name = std.mem.trim(u8, part[0..i], " \t");
                const value = std.mem.trim(u8, part[i + 1 ..], " \t");

                const color = Color.parse(value) orelse return null;

                if (std.mem.eql(u8, name, "sel.fg")) {
                    theme.selected.fg = color;
                } else if (std.mem.eql(u8, name, "sel.bg")) {
                    theme.selected.bg = color;
                } else if (std.mem.eql(u8, name, "def.fg")) {
                    theme.default.fg = color;
                } else if (std.mem.eql(u8, name, "def.bg")) {
                    theme.default.bg = color;
                }
            } else {
                return null;
            }
        }

        return theme;
    }
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

    pub fn parse(repr: []const u8) ?Color {
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

    /// Assumes fg
    pub fn render(self: @This(), r: *Render) !void {
        switch (self) {
            .true => |c| {
                try r.fmt("\x1b[38;2;{};{};{}m", .{ c.red, c.green, c.blue });
            },

            .basic => |c| {
                try r.fmt("\x1b[3{c}m", .{@intFromEnum(c)});
            },
        }
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

test "default selected" {
    var r = render.test_instance;

    try r.render(ColorPair{
        .fg = Color.parse("#24283b").?,
        .bg = Color.parse("#33AA33").?,
    });

    try std.testing.expectEqualSlices(u8, "\x1b[38;2;36;40;59m\x1b[48;2;51;170;51m", r.buffer[0..r.cur]);
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

test "parse theme" {
    try std.testing.expectEqual(Theme.DEFAULT, Theme.parse(""));
    try std.testing.expectEqual(
        Color{ .true = .{ .red = 0, .green = 255, .blue = 0 } },
        (Theme.parse("sel.fg=#00ff00") orelse unreachable).selected.fg,
    );

    try std.testing.expectEqual(
        Color{ .true = .{ .red = 0, .green = 0, .blue = 0xf0 } },
        (Theme.parse("sel.bg=#0000f0") orelse unreachable).selected.bg,
    );

    try std.testing.expectEqual(
        Color{ .true = .{ .red = 255, .green = 0, .blue = 255 } },
        (Theme.parse("def.fg=#ff00ff") orelse unreachable).default.fg,
    );

    try std.testing.expectEqual(
        Color{ .true = .{ .red = 15, .green = 0, .blue = 255 } },
        (Theme.parse("def.bg=#0f00ff") orelse unreachable).default.bg,
    );

    try std.testing.expectEqual(
        ColorPair{
            .bg = Color{ .true = .{ .red = 15, .green = 0, .blue = 255 } },
            .fg = Color{ .true = .{ .red = 0, .green = 255, .blue = 0 } },
        },
        (Theme.parse("def.bg=#0f00ff;def.fg=#00ff00") orelse unreachable).default,
    );

    try std.testing.expectEqual(
        ColorPair{
            .bg = Color{ .true = .{ .red = 15, .green = 0, .blue = 255 } },
            .fg = Color{ .true = .{ .red = 0, .green = 255, .blue = 0 } },
        },
        (Theme.parse("    def.bg   = \t   #0f00ff\t; def.fg   =   #00ff00    ") orelse unreachable).default,
    );
}
