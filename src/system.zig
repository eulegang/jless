const std = @import("std");
const JQ = @import("jq.zig").JQ;

const Inputs = @import("inputs.zig").Inputs;
const Term = @import("term.zig").Term;
const Store = @import("store.zig").Store;
const Render = @import("render.zig").Render;

const log = std.log.scoped(.system);

const State = struct {
    line: usize,
    base: usize,
};

const ColorTheme = struct {
    selected: ColorPair,
    default: ColorPair,
};

const ColorPair = struct {
    fg: u32,
    bg: u32,
};

pub const System = struct {
    inputs: Inputs,
    term: Term,

    store: *Store,
    render: Render,
    state: State,
    theme: ColorTheme,

    filter: ?JQ,
    projection: ?JQ,

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
            .theme = .{
                .default = .{
                    .bg = 0x24_28_3b,
                    .fg = 0x73_7A_A2,
                },
                .selected = .{
                    .fg = 0x33_aa_33,
                    .bg = 0x34_38_4A,
                },
            },
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

        const view = self.store.view(0, self.render.window.height);
        for (0.., view) |i, item| {
            try self.render.move_cursor(@intCast(i), 0);
            if (i == self.state.line) {
                try self.render.true_bg(self.theme.selected.bg);
                try self.render.true_fg(self.theme.selected.fg);
            } else {
                try self.render.true_bg(self.theme.default.bg);
                try self.render.true_fg(self.theme.default.fg);
            }

            try self.render.push_line(item);
            try self.render.flush();
        }

        for (view.len..self.render.window.height) |i| {
            try self.render.move_cursor(@intCast(i), 0);
            try self.render.push_line("");
            try self.render.flush();
        }
    }

    pub fn tick(self: *@This()) !bool {
        const event = try self.inputs.event();
        switch (event) {
            .line => |line| {
                try self.store.push(line);
            },

            .input => |input| {
                log.debug("pre: {}", .{self.state});
                switch (input) {
                    .Quit => return false,
                    .Up => try self.move_up(),
                    .Down => try self.move_down(),

                    else => log.warn("unhandled input {}", .{input}),
                }
                log.debug("post: {}", .{self.state});
            },
        }

        return true;
    }

    pub fn paint_full(self: *@This()) !void {
        const view = self.store.view(self.state.line, self.render.window.height);
        for (0.., view) |i, item| {
            try self.render.move_cursor(@intCast(i), 0);
            if (i == self.state.line) {
                try self.render.true_fg(self.theme.selected.fg);
                try self.render.true_bg(self.theme.selected.bg);
            } else {
                try self.render.true_fg(self.theme.default.fg);
                try self.render.true_bg(self.theme.default.bg);
            }

            try self.render.push_line(item);
            try self.render.flush();
        }

        for (view.len..self.render.window.height) |i| {
            try self.render.move_cursor(@intCast(i), 0);
            try self.render.push_line("");
            try self.render.flush();
        }
    }

    fn move_up(self: *@This()) !void {
        if (self.state.line == 0) {
            if (self.state.base == 0) {
                return;
            } else {
                self.state.base -= 1;
                try self.paint_full();
            }
        } else {
            const prev_line = self.state.line;
            self.state.line -= 1;

            const prev = self.store.list.items[prev_line];
            const line = self.store.list.items[self.state.line];

            try self.render.move_cursor(@intCast(prev_line), 0);
            try self.render.true_bg(self.theme.default.bg);
            try self.render.true_fg(self.theme.default.fg);
            try self.render.push_line(prev);

            try self.render.move_cursor(@intCast(self.state.line), 0);
            try self.render.true_fg(self.theme.default.fg);
            try self.render.true_bg(self.theme.default.bg);
            try self.render.push_line(line);
            try self.render.flush();
        }
    }

    fn move_down(self: *@This()) !void {
        const prev_line = self.state.line;

        if (self.state.line + self.state.base >= self.store.len() -| 1) {
            return;
        }

        self.state.line += 1;

        if (self.store.at(self.state.line)) |line| {
            const prev = self.store.list.items[prev_line];

            try self.render.move_cursor(@intCast(prev_line), 0);
            try self.render.true_bg(self.theme.default.bg);
            try self.render.true_fg(self.theme.default.fg);
            try self.render.push_line(prev);

            try self.render.move_cursor(@intCast(self.state.line), 0);
            try self.render.true_fg(self.theme.selected.fg);
            try self.render.true_bg(self.theme.selected.bg);
            try self.render.push_line(line);
            try self.render.flush();
        }
        if (self.state.line >= self.render.window.height) {
            log.warn("need to implement shift", .{});
        }
    }
};
