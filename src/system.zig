const std = @import("std");
const JQ = @import("jq").JQ;

const index = @import("index.zig");

const Inputs = @import("inputs.zig").Inputs;
const Render = @import("render").Render;
const Term = @import("render").Term;
const Highlighter = @import("highlighter.zig").Highlighter;

const theme = @import("theme.zig");

const view = @import("view.zig");

const log = std.log.scoped(.system);

pub const System = struct {
    inputs: Inputs,
    term: Term,

    store: *index.Store(0x1000),
    render: Render,
    theme: theme.Theme,
    highlighter: Highlighter,
    list_view: view.ListView,
    filter_view: view.FilterView,

    alloc: std.mem.Allocator,

    filter: ?*JQ,
    projection: ?*JQ,

    pub fn init(file: []const u8, alloc: std.mem.Allocator) !*System {
        var self = try alloc.create(System);
        errdefer alloc.destroy(self);

        self.alloc = alloc;

        self.inputs = try Inputs.init();
        self.term = Term.init();

        self.store = try index.Store(0x1000).init(file, alloc);
        self.render = try Render.init(1);

        self.highlighter = try Highlighter.init(.JSON, alloc);
        self.theme = theme.Theme.DEFAULT;
        self.filter = null;
        self.projection = null;

        self.list_view = try view.ListView.init(self);
        self.filter_view = try view.FilterView.init(self);
        return self;
    }

    pub fn close(self: *@This()) void {
        self.inputs.deinit();
        self.store.deinit();
        self.render.deinit();
        self.term.deinit();

        self.alloc.destroy(self);
    }

    pub fn setup(self: *@This()) !void {
        self.term.raw();

        try self.store.build_index();
        try self.store.build_filter(self.filter);

        try self.highlighter.add_lane("[(true) (false)] @bool", self.theme.syntax.json.bool);
        try self.highlighter.add_lane("(null) @null", self.theme.syntax.json.null);
        try self.highlighter.add_lane("[\"{\" \":\" \",\" \"[\" \"]\" \"}\"] @punct", self.theme.syntax.json.punct);
        try self.highlighter.add_lane("(number) @num", self.theme.syntax.json.number);
        try self.highlighter.add_lane("(string) @str", self.theme.syntax.json.string);
        try self.highlighter.add_lane("(pair key: (string) @key)", self.theme.syntax.json.key);

        try self.list_view.paint();
    }

    pub fn tick(self: *@This()) !bool {
        const input = try self.inputs.event();

        switch (input) {
            .list => |li| {
                if (li == .Quit) {
                    return false;
                }

                if (li == .OpenProjection or li == .OpenFilter) {
                    try self.blank_out();

                    self.filter_view.filter = li == .OpenFilter;

                    if (self.filter_view.filter) {
                        if (self.filter) |f| {
                            try self.filter_view.highlighter.load(f.prog);
                        } else {
                            try self.filter_view.highlighter.load(".");
                        }
                    } else {
                        if (self.projection) |p| {
                            try self.filter_view.highlighter.load(p.prog);
                        } else {
                            try self.filter_view.highlighter.load(".");
                        }
                    }

                    self.inputs.mode = .insert;
                    try self.filter_view.paint();
                } else {
                    try self.list_view.handle(li);
                    try self.list_view.paint();
                }
            },

            .insert => |insert| {
                switch (insert) {
                    .Cancel, .Escape => {
                        self.inputs.mode = .list;
                        try self.list_view.paint();
                    },

                    .Submit => {
                        self.inputs.mode = .list;

                        const buffer = self.filter_view.highlighter.buffer();

                        if (JQ.init(buffer, self.alloc)) |jq| {
                            if (self.filter_view.filter) {
                                if (self.filter) |f| {
                                    f.deinit();
                                }

                                self.filter = jq;
                                try self.store.build_filter(self.filter);
                            } else {
                                if (self.projection) |p| {
                                    p.deinit();
                                }

                                self.projection = jq;
                            }
                        } else |err| {
                            log.err("jq error", .{ .expr = buffer, .err = err });
                        }

                        try self.list_view.paint();
                    },

                    else => {
                        try self.filter_view.handle(insert);
                        try self.filter_view.paint();
                    },
                }
            },
        }

        return true;
    }

    pub fn blank_out(self: *@This()) !void {
        var render = self.render;
        try render.render(self.theme.default);

        for (0..render.window.height) |i| {
            try render.move_cursor(@intCast(i), 0);
            try render.push_line("");
            try render.flush();
        }
    }
};
