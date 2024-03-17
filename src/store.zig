const std = @import("std");

const Err = std.mem.Allocator.Error;

pub const Store = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Err!*Store {
        var result = try allocator.create(Store);
        errdefer allocator.destroy(result);

        result.allocator = allocator;

        result.list = std.ArrayList([]const u8).init(allocator);

        return result;
    }

    pub fn push(self: *Store, line: []const u8) Err!void {
        const item = try self.allocator.dupe(u8, line);

        try self.list.append(item);
    }

    pub fn view(self: *Store, base: usize, window: usize) [][]const u8 {
        if (base >= self.list.items.len) {
            return self.list.items[0..0];
        }

        const end = @min(self.list.items.len, base + window);

        return self.list.items[base..end];
    }

    pub fn at(self: *Store, index: usize) ?[]const u8 {
        if (index >= self.list.items.len) {
            return null;
        }

        return self.list.items[index];
    }

    pub fn len(self: *const Store) usize {
        return self.list.items.len;
    }

    pub fn deinit(self: *Store) void {
        for (self.list.items) |item| {
            self.allocator.free(item);
        }

        self.allocator.destroy(self);
    }
};
