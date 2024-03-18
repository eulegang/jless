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

    if (comptime no_format(format)) {
        const entry = .{
            .level = level,
            .scope = scope,
            .msg = format,
            .args = args,
        };

        var buf: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buf);
        var string = std.ArrayList(u8).init(fba.allocator());
        std.json.stringify(entry, .{}, string.writer()) catch return;
        string.append('\n') catch {};

        mutex.lock();
        defer mutex.unlock();

        _ = std.os.write(fd, string.items) catch return;
    } else {
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
}

fn no_format(comptime format: []const u8) bool {
    return std.mem.indexOf(u8, format, "{") == null;
}

fn is_json(comptime args: anytype) bool {
    var json = false;

    switch (@typeInfo(@TypeOf(args))) {
        .Struct => |s| {
            var all_names = true;
            for (s.fields) |f| {
                _ = std.fmt.parseInt(f.name) catch {
                    all_names = false;
                };
            }

            json = all_names;
        },
        else => {},
    }

    return json;
}
