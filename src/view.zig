const std = @import("std");

const Render = @import("render").Render;
const Highlighter = @import("highlighter.zig").Highlighter;
const Theme = @import("theme.zig").Theme;
const system = @import("system.zig");
const inputs = @import("inputs.zig");

const index = @import("index.zig");

const log = std.log.scoped(.view);

pub const ListView = struct {
    sys: *system.System,

    line: usize,
    base: usize,

    pub fn init(sys: *system.System) !ListView {
        return ListView{
            .sys = sys,
            .line = 0,
            .base = 0,
        };
    }

    pub fn handle(self: *@This(), input: inputs.ListInput) !void {
        const page: isize = self.sys.render.window.height;

        switch (input) {
            .Quit => {},
            .Up => try self.move_delta(-1),
            .Down => try self.move_delta(1),

            .HalfPageDown => try self.move_delta(@divTrunc(page, 2)),
            .HalfPageUp => try self.move_delta(-@divTrunc(page, 2)),

            .FullPageDown => try self.move_delta(page),
            .FullPageUp => try self.move_delta(-page),

            .Begin => {
                self.line = 0;
                self.base = 0;
            },

            .End => {
                var delta: isize = @intCast(self.sys.store.len() -| 1);
                delta -|= @intCast(self.line);
                delta -|= @intCast(self.base);
                try self.move_delta(delta);
            },

            else => log.warn("unhandled input {}", .{input}),
        }
    }

    pub fn paint(self: *@This()) !void {
        const top = @min(self.sys.store.len(), self.base + self.sys.render.window.height);
        const theme = self.sys.theme;
        var render = self.sys.render;
        const store = self.sys.store;

        var buffer: [4096]u8 = undefined;
        var n: usize = 0;
        for (0.., self.base..top) |i, store_pos| {
            {
                var fslice = try store.at(store_pos) orelse break;
                defer fslice.deinit();
                n = fslice.read(&buffer);
            }

            try render.move_cursor(@intCast(i), 0);
            if (i == self.line) {
                try render.render(theme.selected);
            } else {
                try render.render(theme.default);
            }

            if (self.sys.projection) |proj| {
                const line = proj.project(buffer[0..n]) catch "error!";

                try self.sys.highlighter.load(line);
                try render.render(self.sys.highlighter);
                try render.push_phantom_pad(line);
            } else {
                try self.sys.highlighter.load(buffer[0..n]);
                try render.render(self.sys.highlighter);
                try render.push_phantom_pad(buffer[0..n]);
            }

            try render.flush();
        }

        try render.render(self.sys.theme.default);

        if (top < render.window.height) {
            for (top..render.window.height) |i| {
                try render.move_cursor(@intCast(i), 0);
                try render.push_line("");
                try render.flush();
            }
        }
    }

    pub fn move_delta(self: *@This(), delta: isize) !void {
        const d: usize = @intCast(@abs(delta));
        if (delta < 0) {
            if (d > self.line) {
                self.base -|= d -| self.line;
                self.line = 0;
            } else {
                self.line -= d;
            }
        } else {
            const cap = self.sys.store.len();
            self.line += d;

            if (self.line >= self.sys.render.window.height - 1) {
                const diff = 1 + self.line -| self.sys.render.window.height;

                self.base += diff;
                self.line -= diff;
            }

            if (self.line + self.base >= cap) {
                const diff = (self.line + self.base) - (cap - 1);
                log.debug("overflow check", .{
                    .store = cap,
                    .diff = diff,
                    .line = self.line,
                    .base = self.base,
                });

                if (diff > self.base) {
                    self.line -= diff - self.base;
                    self.base = 0;
                } else {
                    self.base -= diff;
                }
            }
        }
    }
};

pub const FilterView = struct {
    sys: *system.System,
    filter: bool,
    highlighter: Highlighter,

    buffer: []u8,
    cur: usize,

    pub fn init(sys: *system.System) !FilterView {
        const buffer = try sys.alloc.alloc(u8, 4096);
        var highlighter = try Highlighter.init(.JQ, sys.alloc);

        try highlighter.add_lane("(comment) @comment", sys.theme.syntax.jq.comment);
        try highlighter.add_lane("(number) @num", sys.theme.syntax.jq.number);
        try highlighter.add_lane("(string) @str", sys.theme.syntax.jq.string);
        try highlighter.add_lane("(format) @str", sys.theme.syntax.jq.string);
        try highlighter.add_lane("[\"true\" \"false\"] @bool", sys.theme.syntax.jq.boolean);
        try highlighter.add_lane("(index (identifier) @property)", sys.theme.syntax.jq.key);

        try highlighter.add_lane("[\"[\" \"]\" \"{\" \"}\" \"(\" \")\" ] @punctuation.bracket", sys.theme.syntax.jq.punct);
        try highlighter.add_lane("[ \";\" \",\" \":\" ] @punctuation.delimiter", sys.theme.syntax.jq.delim);

        try highlighter.add_lane(
            \\[
            \\  "def"
            \\  "as"
            \\  "label"
            \\  "module"
            \\  "break"
            \\  "if"
            \\  "then"
            \\  "elif"
            \\  "else"
            \\  "end"
            \\  "try"
            \\  "catch"
            \\  "or"
            \\  "and"
            \\] @keyword
        , sys.theme.syntax.jq.keyword);

        try highlighter.add_lane(
            \\[
            \\  "."
            \\  "=="
            \\  "!="
            \\  ">"
            \\  ">="
            \\  "<="
            \\  "<"
            \\  "="
            \\  "+"
            \\  "-"
            \\  "*"
            \\  "/"
            \\  "%"
            \\  "+="
            \\  "-="
            \\  "*="
            \\  "/="
            \\  "%="
            \\  "//="
            \\  "|"
            \\  "?"
            \\  "//"
            \\  "?//"
            \\ (recurse) ; ".."
            \\] @op
        , sys.theme.syntax.jq.operator);

        try highlighter.add_lane(
            \\((funcname) @function.builtin
            \\  (#any-of? @function.builtin
            \\    "IN" "INDEX" "JOIN" "acos" "acosh" "add" "all" "any" "arrays" "ascii_downcase" "ascii_upcase"
            \\    "asin" "asinh" "atan" "atan2" "atanh" "booleans" "bsearch" "builtins" "capture" "cbrt" "ceil"
            \\    "combinations" "contains" "copysign" "cos" "cosh" "debug" "del" "delpaths" "drem" "empty"
            \\    "endswith" "env" "erf" "erfc" "error" "exp" "exp10" "exp2" "explode" "expm1" "fabs" "fdim"
            \\    "finites" "first" "flatten" "floor" "fma" "fmax" "fmin" "fmod" "format" "frexp" "from_entries"
            \\    "fromdate" "fromdateiso8601" "fromjson" "fromstream" "gamma" "get_jq_origin" "get_prog_origin"
            \\    "get_search_list" "getpath" "gmtime" "group_by" "gsub" "halt" "halt_error" "has" "hypot"
            \\    "implode" "in" "index" "indices" "infinite" "input" "input_filename" "input_line_number"
            \\    "inputs" "inside" "isempty" "isfinite" "isinfinite" "isnan" "isnormal" "iterables" "j0" "j1"
            \\    "jn" "join" "keys" "keys_unsorted" "last" "ldexp" "leaf_paths" "length" "lgamma" "lgamma_r"
            \\    "limit" "localtime" "log" "log10" "log1p" "log2" "logb" "ltrimstr" "map" "map_values" "match"
            \\    "max" "max_by" "min" "min_by" "mktime" "modf" "modulemeta" "nan" "nearbyint" "nextafter"
            \\    "nexttoward" "normals" "not" "now" "nth" "nulls" "numbers" "objects" "path" "paths" "pow"
            \\    "pow10" "range" "recurse" "recurse_down" "remainder" "repeat" "reverse" "rindex" "rint" "round"
            \\    "rtrimstr" "scalars" "scalars_or_empty" "scalb" "scalbln" "scan" "select" "setpath"
            \\    "significand" "sin" "sinh" "sort" "sort_by" "split" "splits" "sqrt" "startswith" "stderr"
            \\    "strflocaltime" "strftime" "strings" "strptime" "sub" "tan" "tanh" "test" "tgamma" "to_entries"
            \\    "todate" "todateiso8601" "tojson" "tonumber" "tostream" "tostring" "transpose" "trunc"
            \\    "truncate_stream" "type" "unique" "unique_by" "until" "utf8bytelength" "values" "walk" "while"
            \\    "with_entries" "y0" "y1" "yn"))
        , sys.theme.syntax.jq.builtin);

        return FilterView{
            .sys = sys,
            .filter = true,
            .highlighter = highlighter,
            .buffer = buffer,
            .cur = 0,
        };
    }

    pub fn deinit(self: @This()) void {
        self.highlighter.deinit();
        self.sys.alloc.free(self.buffer);
    }

    pub fn paint(self: *@This()) !void {
        const bound = self.calc_bound();
        //try self.highlighter.load(self.buffer[0..self.cur]);
        try self.draw_box(bound);
        try self.draw_content(bound);
    }

    fn draw_content(self: *@This(), b: Bound) !void {
        var render = self.sys.render;

        try render.move_cursor(b.y + 1, b.x + 3);
        try render.render(self.highlighter);
        try render.blanks(b.width -| self.cur -| 2);
        try render.flush();
    }

    fn draw_box(self: *@This(), b: Bound) !void {
        var render = self.sys.render;
        const theme = self.sys.theme;

        if (self.highlighter.tree) |tree| {
            log.debug("root range", .{ .root = tree.root().range() });
            if (tree.root().has_error()) {
                try render.render(theme.filter.fail);
            } else {
                try render.render(theme.filter.success);
            }
        } else {
            log.debug("no tree", .{});
        }

        const corners = [4][3]u8{
            .{ 0xe2, 0x95, 0xad },
            .{ 0xe2, 0x95, 0xae },
            .{ 0xe2, 0x95, 0xb0 },
            .{ 0xe2, 0x95, 0xaf },
        };

        const pipes = [2][3]u8{
            .{ 0xe2, 0x94, 0x80 },
            .{ 0xe2, 0x94, 0x82 },
        };

        try render.move_cursor(b.y, b.x);

        try render.raw(&corners[0]);
        for (0..b.width) |i| {
            _ = i;
            try render.raw(&pipes[0]);
        }

        try render.raw(&corners[1]);
        try render.flush();

        for (1..b.height) |h| {
            try render.move_cursor(@intCast(b.y + h), b.x);
            try render.raw(&pipes[1]);
            try render.move_cursor(@intCast(b.y + h), b.x + b.width + 1);
            try render.raw(&pipes[1]);
        }

        try render.flush();

        try render.move_cursor(@intCast(b.y + b.height), b.x);
        try render.raw(&corners[2]);
        for (0..b.width) |i| {
            _ = i;
            try render.raw(&pipes[0]);
        }

        try render.raw(&corners[3]);
        try render.flush();
    }

    pub fn handle(self: *@This(), input: inputs.InsertInput) !void {
        switch (input) {
            .Raw => |r| {
                try self.highlighter.push(r);
                //self.buffer[self.cur] = r;
                //self.cur += 1;
            },

            .BS => {
                try self.highlighter.pop();
                //self.cur -|= 1;
            },

            else => {},
        }
    }

    const Bound = struct {
        x: u16,
        y: u16,
        width: u16,
        height: u16,
    };

    fn calc_bound(self: *@This()) Bound {
        const x: u16 = self.sys.render.window.width / 4;
        const y: u16 = self.sys.render.window.height / 4;

        const width = (self.sys.render.window.width / 2);
        const height: u16 = @intCast(std.mem.count(u8, self.buffer[0..self.cur], "\n") + 2);

        return Bound{
            .x = x,
            .y = y,
            .width = width,
            .height = height,
        };
    }
};
