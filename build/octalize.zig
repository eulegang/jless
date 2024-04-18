const std = @import("std");

pub fn octalize(writer: anytype, filename: []const u8) !void {
    const dir = std.fs.cwd();
    const file = try dir.openFile(filename, .{ .mode = .read_only });
    var buffer: [1024]u8 = undefined;
    var read: usize = 1;
    var written: usize = 0;

    while (read != 0) {
        read = try file.read(&buffer);
        const slice = buffer[0..read];

        for (slice) |ch| {
            try writer.print("0{o}, ", .{ch});
            written += 1;

            if (written % 16 == 15) {
                try writer.print("\n", .{});
            }
        }
    }
}
