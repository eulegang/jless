const std = @import("std");

const ts = @import("tree-sitter");
const theme = @import("theme.zig");
const render = @import("render");

const Render = render.Render;

const log = std.log.scoped(.highlighter);

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

    lang: ts.Lang,
    parser: ts.TS,
    tree: ?ts.Tree,
    buf: []u8,
    len: usize,

    pub fn init(lang: ts.Lang, alloc: std.mem.Allocator) !@This() {
        const parser = try ts.TS.init(lang);

        const lanes = std.ArrayList(Lane).init(alloc);
        const states = std.ArrayList(State).init(alloc);
        const buf = try alloc.alloc(u8, 4096);

        return Highlighter{
            .lanes = lanes,
            .states = states,

            .parser = parser,
            .lang = lang,
            .tree = null,

            .buf = buf,
            .len = 0,
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
        self.alloc.free(self.buf);
    }

    pub fn buffer(self: *const @This()) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn add_lane(self: *@This(), query: []const u8, color: theme.Color) !void {
        const q = try ts.Query.init(self.lang, query);

        try self.lanes.append(Lane{
            .query = q,
            .color = color,
        });
    }

    pub fn load(self: *@This(), line: []const u8) !void {
        log.debug("loading", .{ .line = line });
        std.mem.copyForwards(u8, self.buf[0..line.len], line);
        self.len = line.len;

        const tree = try self.parser.parse(self.buf[0..self.len], null);
        if (self.tree) |t| {
            t.deinit();
        }

        self.tree = tree;

        try self.reload_states(tree);
    }

    fn reload_cached(self: *@This()) !void {
        const tree = try self.parser.parse(self.buf[0..self.len], self.tree);

        self.tree = tree;
        try self.reload_states(tree);
    }

    fn reload_states(self: *@This(), tree: ts.Tree) !void {
        for (self.states.items) |state| {
            state.cursor.deinit();
        }

        self.states.clearRetainingCapacity();
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

    pub fn push(self: *@This(), ch: u8) !void {
        const old_len = self.len;
        self.buf[self.len] = ch;
        self.len += 1;

        log.debug("push", .{ .buffer = self.buf[0..self.len], .len = self.len });

        if (self.tree) |t| {
            t.edit(ts.InputEdit{
                .start_byte = 0,
                .old_end_byte = @intCast(old_len),
                .new_end_byte = @intCast(self.len),
                .start_point = .{ .row = 0, .column = 0 },
                .old_end_point = .{ .row = 0, .column = @intCast(old_len) },
                .new_end_point = .{ .row = 0, .column = @intCast(self.len) },
            });

            try self.reload_cached();
        }
    }

    pub fn pop(self: *@This()) !void {
        if (self.len > 0) {
            const old_len = self.len;
            self.len -= 1;

            log.debug("push", .{ .buffer = self.buf[0..self.len] });

            if (self.tree) |t| {
                t.edit(ts.InputEdit{
                    .start_byte = 0,
                    .old_end_byte = @intCast(old_len),
                    .new_end_byte = @intCast(self.len),
                    .start_point = .{ .row = 0, .column = 0 },
                    .old_end_point = .{ .row = 0, .column = @intCast(old_len) },
                    .new_end_point = .{ .row = 0, .column = @intCast(self.len) },
                });

                try self.reload_cached();
            }
        }
    }

    pub fn render(self: *const @This(), r: *Render) !void {
        try run_highlight(self.buf[0..self.len], r, self.lanes.items, self.states.items);
    }
};

fn run_highlight(buf: []const u8, r: *Render, lanes: []Lane, states: []State) !void {
    var cur: usize = 0;
    var color: theme.Color = .{ .basic = .Default };

    while (cur < buf.len) {
        var hare = buf.len;
        for (lanes, states) |lane, *state| {
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
        try r.fmt("{s}", .{buf[cur..hare]});
        cur = hare;
    }
}

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
