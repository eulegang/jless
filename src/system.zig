const std = @import("std");
const JQ = @import("jq.zig").JQ;

const Inputs = @import("inputs.zig").Inputs;
const Term = @import("term.zig").Term;
const Store = @import("store.zig").Store;
const Render = @import("render.zig").Render;

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
            .filter = null,
            .projection = null,
        };
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
                try self.render.true_fg(0x33_aa_33);
                try self.render.true_bg(0x34_38_4A);
            } else {
                try self.render.true_bg(0x24_28_3b);
                try self.render.true_fg(0x73_7A_A2);
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
                if (input == .Quit) {
                    return false;
                }
            },
        }

        return true;
    }

    pub fn close(self: *@This()) void {
        self.inputs.close();
        self.store.deinit();
        self.render.deinit();
        self.term.deinit();
    }
};
