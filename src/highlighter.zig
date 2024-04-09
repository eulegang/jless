const std = @import("std");

const ts = @import("tree-sitter");
const theme = @import("theme.zig");
const render = @import("render");

const Render = render.Render;

const Lane = struct {
    query: ts.Query,
    color: theme.Color,
};

const State = struct {
    next: ?usize,
    cursor: ts.QueryCursor,

    fn forward(self: *@This(), cur: usize) void {
        while (self.cursor.next()) |node| {
            const range = node.range();

            if (range.start >= cur) {
                self.next = range.start;
                break;
            }
        }
    }
};

pub const Highlighter = struct {
    lanes: std.ArrayList(Lane),
    states: std.ArrayList(State),

    color: theme.Color,
    lang: ts.Lang,
    parser: ts.TS,
    tree: ?ts.Tree,
    line: []const u8,
    cur: usize,

    pub fn init(lang: ts.Lang, alloc: std.mem.Allocator) !@This() {
        const parser = try ts.TS.init(lang);

        const lanes = std.ArrayList(Lane).init(alloc);
        const states = std.ArrayList(State).init(alloc);

        return Highlighter{
            .lanes = lanes,
            .states = states,
            .color = .{ .basic = .Default },

            .parser = parser,
            .lang = lang,
            .tree = null,

            .line = "",
            .cur = 0,
        };
    }

    pub fn deinit(self: *@This()) void {
        for (self.lanes.items) |lane| {
            lane.query.deinit();
        }

        self.lanes.deinit();

        for (self.states.items) |state| {
            state.cursor.deinit();
        }

        self.states.deinit();

        if (self.tree) |tree| {
            tree.deinit();
        }

        self.parser.deinit();
    }

    pub fn add_lane(self: *@This(), query: []const u8, color: theme.Color) !void {
        const q = try ts.Query.init(self.lang, query);

        try self.lanes.append(Lane{
            .query = q,
            .color = color,
        });
    }

    pub fn load(self: *@This(), line: []const u8) !void {
        self.line = line;
        self.cur = 0;

        for (self.states.items) |state| {
            state.cursor.deinit();
        }

        self.states.clearRetainingCapacity();

        const tree = try self.parser.parse(line, null);
        if (self.tree) |t| {
            t.deinit();
        }

        self.tree = tree;

        for (self.lanes.items) |lane| {
            var cursor = try ts.QueryCursor.init(lane.query, tree.root());
            var next: ?usize = null;

            if (cursor.next()) |node| {
                next = node.range().start;
            }

            try self.states.append(State{
                .cursor = cursor,
                .next = next,
            });
        }
    }

    pub fn render(self: @This(), r: *Render) !void {
        var cur: usize = 0;
        var color: theme.Color = .{ .basic = .Default };

        while (cur < self.line.len) {
            var hare = self.line.len;
            for (self.lanes.items, self.states.items) |lane, *state| {
                if (state.next) |n| {
                    if (n < cur) {
                        state.forward(cur);
                    }
                }

                if (state.next) |n| {
                    if (n == cur) {
                        color = lane.color;
                    }

                    if (n > cur) {
                        hare = @min(hare, n);
                    }
                }
            }

            try r.render(color);
            try r.fmt("{s}", .{self.line[cur..hare]});
            cur = hare;
        }
    }
};

test "punct" {
    var r = render.test_instance;

    var highlighter = try Highlighter.init(.JSON, std.testing.allocator);
    defer highlighter.deinit();

    try highlighter.add_lane("[\"{\" \":\" \",\" \"[\" \"]\" \"}\"] @punct", .{ .basic = .Yellow });

    const line = "{}";
    const expected = "\x1b[33m{}";

    try highlighter.load(line);

    try r.render(&highlighter);

    try std.testing.expectEqualSlices(u8, expected, r.buffer[0..r.cur]);
}

test "keywords" {
    var r = render.test_instance;

    var highlighter = try Highlighter.init(.JSON, std.testing.allocator);
    defer highlighter.deinit();

    try highlighter.add_lane("[(true) (false) (null)] @kw", .{ .basic = .Magenta });

    var line: []const u8 = "true";
    var expected: []const u8 = "\x1b[35mtrue";

    try highlighter.load(line);
    try r.render(highlighter);
    try std.testing.expectEqualSlices(u8, expected, r.buffer[0..r.cur]);

    r.cur = 0;

    line = "null";
    expected = "\x1b[35mnull";

    try highlighter.load(line);
    try r.render(highlighter);
    try std.testing.expectEqualSlices(u8, expected, r.buffer[0..r.cur]);

    r.cur = 0;

    line = "false";
    expected = "\x1b[35mfalse";

    try highlighter.load(line);
    try r.render(highlighter);
    try std.testing.expectEqualSlices(u8, expected, r.buffer[0..r.cur]);
}

test "array/keywords" {
    var r = render.test_instance;

    var highlighter = try Highlighter.init(.JSON, std.testing.allocator);
    defer highlighter.deinit();

    try highlighter.add_lane("[(true) (false) (null)] @kw", .{ .basic = .Magenta });
    try highlighter.add_lane("[\"{\" \":\" \",\" \"[\" \"]\" \"}\"] @punct", .{ .basic = .Yellow });

    const line: []const u8 = "[true, false, null]";
    const expected: []const u8 = "\x1b[33m[\x1b[35mtrue\x1b[33m, \x1b[35mfalse\x1b[33m, \x1b[35mnull\x1b[33m]";

    try highlighter.load(line);
    try r.render(highlighter);
    try std.testing.expectEqualSlices(u8, expected, r.buffer[0..r.cur]);
}

test "object/keys prio" {
    var r = render.test_instance;

    var highlighter = try Highlighter.init(.JSON, std.testing.allocator);
    defer highlighter.deinit();

    try highlighter.add_lane("[(true) (false) (null)] @kw", .{ .basic = .Magenta });
    try highlighter.add_lane("[\"{\" \":\" \",\" \"[\" \"]\" \"}\"] @punct", .{ .basic = .Yellow });
    try highlighter.add_lane("(string) @str", .{ .basic = .Green });
    try highlighter.add_lane("(pair key: (string) @key)", .{ .basic = .Blue });

    const line: []const u8 = "{\"null\": null, \"str\": \"string\"}";
    const expected: []const u8 = "\x1b[33m{\x1b[34m\"null\"\x1b[33m: \x1b[35mnull\x1b[33m, \x1b[34m\"str\"\x1b[33m: \x1b[32m\"string\"\x1b[33m}";

    try highlighter.load(line);
    try r.render(highlighter);
    try std.testing.expectEqualSlices(u8, expected, r.buffer[0..r.cur]);
}
