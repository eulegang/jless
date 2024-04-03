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

    filter: ?*JQ,
    projection: ?*JQ,

    pub fn init(file: []const u8, alloc: std.mem.Allocator) !*System {
        var self = try alloc.create(System);
        errdefer alloc.destroy(self);

        self.inputs = try Inputs.init();
        self.term = Term.init();

        self.store = try index.Store(0x1000).init(file, alloc);
        self.render = try Render.init(1);

        self.highlighter = try Highlighter.init(alloc);
        self.theme = theme.Theme.DEFAULT;
        self.filter = null;
        self.projection = null;

        self.list_view = try view.ListView.init(self);
        return self;
    }

    pub fn close(self: *@This()) void {
        self.inputs.deinit();
        self.store.deinit();
        self.render.deinit();
        self.term.deinit();
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

                try self.list_view.handle(li);
                try self.list_view.paint();
            },
        }

        return true;
    }
};
