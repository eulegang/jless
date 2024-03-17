const std = @import("std");

var fd: std.os.fd_t = 0;
var mutex = std.Thread.Mutex{};

pub fn jsonLog(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    if (fd == 0) {
        if (std.os.getenv("JLESS_LOG")) |name| {
            fd = std.os.open(name, .{
                .ACCMODE = .WRONLY,
                .CREAT = true,
                .APPEND = true,
            }, 0o644) catch -1;
        } else {
            fd = -1;
        }
    }

    if (fd == -1) {
        return;
    }

    var msg_buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, format, args) catch return;
    const entry = .{
        .level = level,
        .scope = scope,
        .msg = msg,
    };

    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var string = std.ArrayList(u8).init(fba.allocator());
    std.json.stringify(entry, .{}, string.writer()) catch return;
    string.append('\n') catch {};

    mutex.lock();
    defer mutex.unlock();

    _ = std.os.write(fd, string.items) catch return;
}
