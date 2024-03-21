const std = @import("std");
const JQ = @import("jq.zig").JQ;

const Inputs = @import("inputs.zig").Inputs;
const Term = @import("term.zig").Term;
const Store = @import("store.zig").Store;
const Render = @import("render.zig").Render;

const theme = @import("theme.zig");

const log = std.log.scoped(.system);

const State = struct {
    line: usize,
    base: usize,
};

pub const System = struct {
    inputs: Inputs,
    term: Term,

    store: *Store,
    render: Render,
    state: State,
    theme: theme.Theme,

    filter: ?*JQ,
    projection: ?*JQ,

    pub fn init(file: ?[]const u8, alloc: std.mem.Allocator) !System {
        const inputs = try Inputs.init(file);
        const term = Term.init();

        const store = try Store.init(alloc);
        const render = try Render.init(1);
        const state = State{ .line = 0, .base = 0 };

        return System{
            .inputs = inputs,
            .term = term,
            .store = store,
            .render = render,
            .state = state,
            .theme = theme.Theme.DEFAULT,
            .filter = null,
            .projection = null,
        };
    }

    pub fn close(self: *@This()) void {
        self.inputs.close();
        self.store.deinit();
        self.render.deinit();
        self.term.deinit();
    }

    pub fn setup(self: *@This()) !void {
        self.term.raw();

        while (try self.inputs.load_gen()) |line| {
            try self.store.push(line);
        }

        try self.paint_full();
    }

    pub fn tick(self: *@This()) !bool {
        const event = try self.inputs.event();
        switch (event) {
            .line => |line| {
                try self.store.push(line);
            },

            .input => |input| {
                log.debug("pretick", .{ .state = self.state, .window = self.render.window });
                const page: isize = self.render.window.height;
                switch (input) {
                    .Quit => return false,
                    .Up => try self.move_delta(-1),
                    .Down => try self.move_delta(1),

                    .HalfPageDown => try self.move_delta(@divTrunc(page, 2)),
                    .HalfPageUp => try self.move_delta(-@divTrunc(page, 2)),

                    .FullPageDown => try self.move_delta(page),
                    .FullPageUp => try self.move_delta(-page),

                    .Begin => {
                        self.state = .{ .line = 0, .base = 0 };
                        try self.paint_full();
                    },

                    .End => {
                        var delta: isize = @intCast(self.store.len() -| 1);
                        delta -|= @intCast(self.state.line);
                        delta -|= @intCast(self.state.base);
                        try self.move_delta(delta);
                        try self.paint_full();
                    },

                    else => log.warn("unhandled input {}", .{input}),
                }

                log.debug("posttick", .{ .state = self.state, .window = self.render.window });
            },
        }

        return true;
    }

    pub fn paint_full(self: *@This()) !void {
        const view = self.store.view(self.state.base, self.render.window.height);

        //log.debug("projector {?*}", .{self.projection});
        for (0.., view) |i, item| {
            try self.render.move_cursor(@intCast(i), 0);
            if (i == self.state.line) {
                try self.render.render(self.theme.selected);
            } else {
                try self.render.render(self.theme.default);
            }

            if (self.projection) |proj| {
                const line = proj.project(item) catch "error!";
                try self.render.push_line(line);
            } else {
                try self.render.push_line(item);
            }
            //try self.render.push_line(item);

            try self.render.flush();
        }

        try self.render.render(self.theme.default);

        for (view.len..self.render.window.height) |i| {
            try self.render.move_cursor(@intCast(i), 0);
            try self.render.push_line("");
            try self.render.flush();
        }
    }

    fn move_delta(self: *@This(), delta: isize) !void {
        const d: usize = @intCast(@abs(delta));
        if (delta < 0) {
            if (d > self.state.line) {
                self.state.base -|= d -| self.state.line;
                self.state.line = 0;
            } else {
                self.state.line -= d;
            }
        } else {
            self.state.line += d;

            if (self.state.line >= self.render.window.height - 1) {
                const diff = 1 + self.state.line -| self.render.window.height;

                self.state.base += diff;
                self.state.line -= diff;
            }

            if (self.state.line + self.state.base >= self.store.len()) {
                const diff = (self.state.line + self.state.base) - (self.store.len() - 1);
                log.debug("overflow check", .{
                    .store = self.store.len(),
                    .diff = diff,
                    .line = self.state.line,
                    .base = self.state.base,
                });

                if (diff > self.state.base) {
                    self.state.line -= diff - self.state.base;
                    self.state.base = 0;
                } else {
                    self.state.base -= diff;
                }
            }
        }

        try self.paint_full();
    }
};
