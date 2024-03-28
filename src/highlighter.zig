const std = @import("std");

const ts = @import("tree-sitter.zig");
const theme = @import("theme.zig");
const render = @import("render.zig");

const Render = render.Render;

const Lane = struct {
    query: ts.Query,
    color: theme.ColorPair,
};

const State = struct {
    next: ?usize,
    cursor: ts.QueryCursor,
};

const Highlighter = struct {
    lanes: std.ArrayList(Lane),
    states: std.ArrayList(State),

    parser: ts.TS,
    tree: ?ts.Tree,
    line: []const u8,
    cur: usize,

    pub fn init(alloc: std.mem.Allocator) !@This() {
        const parser = try ts.TS.json();

        const lanes = std.ArrayList(Lane).init(alloc);
        const states = std.ArrayList(State).init(alloc);

        return Highlighter{
            .lanes = lanes,
            .states = states,

            .parser = parser,
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
    }

    pub fn add_lane(self: *@This(), query: []const u8, color: theme.ColorPair) !void {
        const q = try ts.Query.json(query);

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

        const tree = try self.parser.parse(line);
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
        try r.fmt("{s}", .{self.line});
    }
};

test "foobar" {
    var r = render.test_instance;

    var highlighter = try Highlighter.init(std.testing.allocator);
    defer highlighter.deinit();

    try highlighter.add_lane("[(true) (false) (null)]", .{ .fg = .{ .basic = .Magenta }, .bg = .{ .basic = .Black } });

    const line = "{\"timestamp\":\"2024-03-14T00:55:51.506729Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"hello\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}";
    const expected = "{\"timestamp\":\"2024-03-14T00:55:51.506729Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"hello\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}";

    try highlighter.load(line);

    try r.render(highlighter);

    try std.testing.expectEqualSlices(u8, expected, r.buffer[0..r.cur]);
}

