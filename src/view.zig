const std = @import("std");

const Render = @import("render").Render;
const Highlighter = @import("highlighter.zig").Highlighter;
const Theme = @import("theme.zig").Theme;
const system = @import("system.zig");
const inputs = @import("inputs.zig");

const index = @import("index.zig");

const log = std.log.scoped(.system);

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

    buffer: []u8,

    pub fn init(sys: *system.System) !FilterView {
        const buffer = try sys.alloc.alloc(u8, 4096);
        return FilterView{
            .sys = sys,
            .filter = true,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: @This()) void {
        self.sys.alloc.free(self.buffer);
    }

    pub fn paint(self: *@This()) !void {
        try self.draw_box();
    }

    fn draw_box(self: *@This()) !void {
        var render = self.sys.render;

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

        const x: u16 = render.window.width / 4;
        const y: u16 = render.window.height / 4;

        const width = (render.window.width / 2) -| 2;
        const height: u16 = (3 -| 2);

        try render.move_cursor(y, x);

        try render.raw(&corners[0]);
        for (0..width) |i| {
            _ = i;
            try render.raw(&pipes[0]);
        }

        try render.raw(&corners[1]);
        try render.flush();

        for (0..height) |h| {
            try render.move_cursor(@intCast(y + h + 1), x);
            try render.raw(&pipes[1]);
            try render.move_cursor(@intCast(y + h + 1), x + width + 1);
            try render.raw(&pipes[1]);
        }

        try render.flush();

        try render.move_cursor(@intCast(y + height + 1), x);
        try render.raw(&corners[2]);
        for (0..width) |i| {
            _ = i;
            try render.raw(&pipes[0]);
        }

        try render.raw(&corners[3]);
        try render.flush();
    }

    pub fn handle(self: *@This(), input: inputs.InsertInput) !void {
        _ = self;
        _ = input;
    }
};
