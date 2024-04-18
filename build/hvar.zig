const std = @import("std");

pub const HVar = struct {
    name: []const u8,
    value: union(enum) {
        blank: void,
        number: usize,
        str: []const u8,
    },

    pub fn fmt(b: *std.Build, vars: []const HVar) ![]const u8 {
        var buffer = std.ArrayList(u8).init(b.allocator);
        var writer = buffer.writer();

        for (vars) |v| {
            switch (v.value) {
                .blank => {
                    try writer.print("#define {s}\n", .{v.name});
                },

                .number => |n| {
                    try writer.print("#define {s} {}\n", .{ v.name, n });
                },

                .str => |s| {
                    try writer.print("#define {s} \"{s}\"\n", .{ v.name, s });
                },
            }
        }

        return buffer.items;
    }
};
