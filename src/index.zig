const std = @import("std");
const jsonp = @import("jsonp.zig");
const jq = @import("jq.zig");

const Error = std.os.MMapError || std.os.OpenError || std.mem.Allocator.Error || error{OutOfCachePages};

const PAGE_MASK: usize = 0xFFF;
const PAGE: usize = 0x1000;

const Windower = struct {
    const Window = struct {
        start: u16,
        end: u16,

        fn len(self: Window) usize {
            return @intCast(self.end - self.start);
        }

        fn buffer(self: Window, buf: []const u8) []const u8 {
            return buf[self.start..self.end];
        }
    };

    start: u32,
    end: u32,

    fn next(self: *@This()) ?Window {
        const PAGEu32: u32 = @intCast(PAGE);
        const PAGE_MASKu32: u32 = @intCast(PAGE_MASK);
        if (self.start >= self.end) {
            return null;
        }

        const start = self.start & PAGE_MASK;

        var end = PAGEu32;
        if ((self.end & ~PAGE_MASKu32) == (self.start & ~PAGE_MASKu32)) {
            end = self.end & PAGE_MASKu32;
        }

        self.start = (self.start + PAGEu32) & (~PAGE_MASKu32);

        return Window{
            .start = @intCast(start),
            .end = @intCast(end),
        };
    }
};

pub const Entry = packed struct {
    index: u31,
    mixed: bool,

    fn same_page(self: Entry, other: Entry) bool {
        const ent_page = self.index & ~PAGE_MASK;
        const oth_page = other.index & ~PAGE_MASK;

        return ent_page == oth_page;
    }

    fn offset(self: Entry) usize {
        return self.index & PAGE_MASK;
    }

    fn page(self: Entry) usize {
        return (self.index & ~PAGE_MASK) >> 12;
    }
};

pub fn FSlice(comptime size: usize) type {
    return struct {
        start: u32,
        end: u32,
        pages: std.ArrayList(*Page(size)),

        pub fn read(self: *@This(), buf: []u8) usize {
            var cur: usize = 0;
            var page: usize = 0;
            var windower = Windower{ .start = self.start, .end = self.end };

            while (windower.next()) |window| {
                const dst = buf[cur .. cur + window.len()];
                const src = self.pages.items[page].*.base[window.start..window.end];

                @memcpy(dst, src);

                page += 1;
                cur += window.len();
            }

            return cur;
        }

        pub fn content(self: *const @This()) ?[]const u8 {
            if ((self.start & ~PAGE_MASK) != (self.end & ~PAGE_MASK)) {
                return null;
            }

            return self.pages.items[0].base[self.start..self.end];
        }

        pub fn deinit(self: *@This()) void {
            for (self.pages.items) |p| {
                p.dec();
            }

            self.pages.deinit();
        }
    };
}

const Index = struct {
    const Self = @This();

    valid: std.ArrayList(Entry),
    filter: ?std.ArrayList(usize),

    fn init(alloc: std.mem.Allocator) Self {
        const valid = std.ArrayList(Entry).init(alloc);

        return Self{
            .valid = valid,
            .filter = null,
        };
    }

    fn deinit(self: Self) void {
        self.valid.deinit();

        if (self.filter) |f| {
            f.deinit();
        }
    }
};

pub fn Page(comptime size: usize) type {
    return struct {
        const Self = @This();

        count: usize,
        idx: usize,
        base: []align(std.mem.page_size) u8,
        alloc: std.mem.Allocator,

        fn init(
            alloc: std.mem.Allocator,
            fd: std.os.fd_t,
            page: usize,
        ) Error!*Self {
            const offset = page << 12;
            var self = try alloc.create(Self);
            self.base = try std.os.mmap(null, size, std.os.PROT.READ, .{ .TYPE = .PRIVATE }, fd, offset);
            self.count = 1;
            self.alloc = alloc;
            self.idx = page;
            return self;
        }

        fn inc(self: *Self) void {
            self.count += 1;
        }

        fn dec(self: *Self) void {
            self.count -|= 1;

            if (self.count == 0) {
                std.os.munmap(self.base);
                self.alloc.destroy(self);
            }
        }
    };
}

pub fn Store(comptime size: usize) type {
    if (@popCount(size) != 1 or size < 0x1000) {
        @compileError("store size is not page aligned");
    }

    return struct {
        const Self = @This();

        fd: std.os.fd_t,
        alloc: std.mem.Allocator,
        index: Index,

        caches: [8]?*Page(size),

        pub fn init(file: []const u8, alloc: std.mem.Allocator) Error!*Self {
            const self = try alloc.create(Self);
            errdefer alloc.destroy(self);
            self.alloc = alloc;

            self.fd = try std.os.open(file, .{ .ACCMODE = .RDONLY }, 0o644);
            errdefer std.os.close(self.fd);

            self.index = Index.init(alloc);
            self.caches = .{
                null, null, null, null, null, null, null, null,
            };

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.index.deinit();
            std.os.close(self.fd);

            for (self.caches) |cache| {
                if (cache) |p| {
                    p.dec();
                }
            }

            self.alloc.destroy(self);
        }

        fn page_offset(self: *Self, offset: usize) Error!*Page(size) {
            return try Page(size).init(
                self.alloc,
                self.fd,
                offset,
            );
        }

        fn load_page(self: *Self, page: usize) Error!*Page(size) {
            var empty: ?usize = null;
            var unused: ?usize = null;

            for (0.., self.caches) |i, cache| {
                if (cache) |p| {
                    if (p.idx == page) {
                        return p;
                    }

                    if (p.count == 1 and unused == null) {
                        unused = i;
                    }
                } else if (empty == null) {
                    empty = i;
                }
            }

            if (empty) |i| {
                const p = try self.page_offset(page);
                self.caches[i] = p;
                return p;
            }

            if (unused) |i| {
                self.caches[i].?.dec();

                const p = try self.page_offset(page);
                self.caches[i] = p;
                return p;
            }

            return Error.OutOfCachePages;
        }

        pub fn build_index(self: *Self) !void {
            if (self.index.valid.items.len > 0) {
                self.index.valid.clearRetainingCapacity();
            }

            const file_size: usize = @intCast((try std.os.fstat(self.fd)).size);
            const json_state = try jsonp.JsonP.init(self.alloc);
            defer json_state.deinit(self.alloc);

            var p = try self.page_offset(0);
            var page_idx: usize = 0;
            var start: usize = 0;

            for (0..file_size) |i| {
                const p_off = (i & ~PAGE_MASK) >> 12;
                const b_off = i & PAGE_MASK;

                if (page_idx != p_off) {
                    p.dec();
                    page_idx = p_off;

                    p = try self.page_offset(p_off);
                }

                const b = p.base[b_off];

                if (try json_state.visit(b)) |state| {
                    const mixed: bool = switch (state) {
                        .Success => false,
                        .Failed => true,
                    };

                    const entry = Entry{
                        .mixed = mixed,
                        .index = @intCast(start),
                    };

                    try self.index.valid.append(entry);
                    start = i + 1;
                }
            }

            const entry = Entry{
                .mixed = false,
                .index = @intCast(start),
            };

            try self.index.valid.append(entry);

            p.dec();
        }

        pub fn build_filter(self: *Self, jq_o: ?*jq.JQ) !void {
            if (self.index.filter) |f| {
                f.deinit();
                self.index.filter = null;
            }

            var arr = std.ArrayList(usize).init(self.alloc);
            var buf: [0x1000]u8 = undefined;
            var n: usize = 0;

            if (jq_o) |filter| {
                for (0..self.index.valid.items.len) |idx| {
                    {
                        var slice = try self.at(idx) orelse break;
                        defer slice.deinit();

                        if (slice.content()) |c| {
                            if (try filter.predicate(c)) {
                                try arr.append(idx);
                            }
                        } else {
                            n = slice.read(&buf);

                            if (try filter.predicate(buf[0..n])) {
                                try arr.append(idx);
                            }
                        }
                    }
                }

                self.index.filter = arr;
            }
        }

        pub fn at(self: *Self, idx: usize) Error!?FSlice(size) {
            var entry: Entry = undefined;
            var end: Entry = undefined;
            if (self.index.filter) |f| {
                if (f.items.len <= idx) {
                    return null;
                }

                const i = f.items[idx];

                entry = self.index.valid.items[i];
                end = self.index.valid.items[i + 1];
            } else {
                if (self.index.valid.items.len - 1 <= idx) {
                    return null;
                }

                entry = self.index.valid.items[idx];
                end = self.index.valid.items[idx + 1];
            }

            var slice = FSlice(size){
                .start = @intCast(entry.offset()),
                .end = @intCast((end.index - 1) - (entry.index & ~PAGE_MASK)),
                .pages = std.ArrayList(*Page(size)).init(self.alloc),
            };

            for (entry.page()..end.page() + 1) |i| {
                var page = try self.load_page(i);
                page.inc();
                try slice.pages.append(page);
            }

            return slice;
        }

        pub fn len(self: *Self) usize {
            if (self.index.filter) |f| {
                return f.items.len;
            }

            return self.index.valid.items.len -| 1;
        }
    };
}

test "sample.log with fslice read" {
    var store = try Store(0x1000).init("sample.log", std.testing.allocator);
    defer store.deinit();

    try store.build_index();

    var buf: [4096]u8 = undefined;

    try std.testing.expectEqual(6, store.len());

    {
        var slice = try store.at(0) orelse @panic("no storage");
        defer slice.deinit();
        const n = slice.read(&buf);

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506729Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"hello\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            buf[0..n],
        );
    }

    {
        var slice = try store.at(1) orelse @panic("no storage");
        defer slice.deinit();
        const n = slice.read(&buf);

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506797Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"world\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            buf[0..n],
        );
    }

    {
        var slice = try store.at(2) orelse @panic("no storage");
        defer slice.deinit();
        const n = slice.read(&buf);

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506811Z\",\"level\":\"WARN\",\"fields\":{\"message\":\"do well\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            buf[0..n],
        );
    }

    {
        var slice = try store.at(3) orelse @panic("no storage");
        defer slice.deinit();
        const n = slice.read(&buf);

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506824Z\",\"level\":\"DEBUG\",\"fields\":{\"message\":\"often\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            buf[0..n],
        );
    }

    {
        var slice = try store.at(4) orelse @panic("no storage");
        defer slice.deinit();
        const n = slice.read(&buf);

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506836Z\",\"level\":\"TRACE\",\"fields\":{\"message\":\"never\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            buf[0..n],
        );
    }

    {
        var slice = try store.at(5) orelse @panic("no storage");
        defer slice.deinit();
        const n = slice.read(&buf);

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506847Z\",\"level\":\"ERROR\",\"fields\":{\"message\":\"is to human\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            buf[0..n],
        );
    }

    try std.testing.expectEqual(null, try store.at(6));
}

test "sample.log with fslice content" {
    var store = try Store(0x1000).init("sample.log", std.testing.allocator);
    defer store.deinit();

    try store.build_index();
    try std.testing.expectEqual(6, store.len());

    {
        var slice = try store.at(0) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506729Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"hello\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    {
        var slice = try store.at(1) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506797Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"world\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    {
        var slice = try store.at(2) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506811Z\",\"level\":\"WARN\",\"fields\":{\"message\":\"do well\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    {
        var slice = try store.at(3) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506824Z\",\"level\":\"DEBUG\",\"fields\":{\"message\":\"often\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    {
        var slice = try store.at(4) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506836Z\",\"level\":\"TRACE\",\"fields\":{\"message\":\"never\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    {
        var slice = try store.at(5) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506847Z\",\"level\":\"ERROR\",\"fields\":{\"message\":\"is to human\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    try std.testing.expectEqual(null, try store.at(6));
}

test "windowing" {
    var windower = Windower{
        .start = 0,
        .end = 157,
    };

    try std.testing.expectEqual(Windower.Window{ .start = 0, .end = 157 }, windower.next().?);
    try std.testing.expectEqual(null, windower.next());

    windower = Windower{
        .start = 0xFF5,
        .end = 0x1005,
    };

    try std.testing.expectEqual(Windower.Window{ .start = 0xFF5, .end = 0x1000 }, windower.next().?);
    try std.testing.expectEqual(Windower.Window{ .start = 0x000, .end = 0x0005 }, windower.next().?);
    try std.testing.expectEqual(null, windower.next());

    windower = Windower{
        .start = 0xFF5,
        .end = 0x1005,
    };

    try std.testing.expectEqual(Windower.Window{ .start = 0xFF5, .end = 0x1000 }, windower.next().?);
    try std.testing.expectEqual(Windower.Window{ .start = 0x000, .end = 0x0005 }, windower.next().?);
    try std.testing.expectEqual(null, windower.next());

    windower = Windower{
        .start = 0x045,
        .end = 0x2005,
    };

    try std.testing.expectEqual(Windower.Window{ .start = 0x045, .end = 0x1000 }, windower.next().?);
    try std.testing.expectEqual(Windower.Window{ .start = 0x000, .end = 0x1000 }, windower.next().?);
    try std.testing.expectEqual(Windower.Window{ .start = 0x000, .end = 0x0005 }, windower.next().?);
    try std.testing.expectEqual(null, windower.next());
}

test "filter" {
    var store = try Store(0x1000).init("sample.log", std.testing.allocator);
    defer store.deinit();

    const filter = try jq.JQ.init(".level == \"INFO\"", std.testing.allocator);
    defer filter.deinit();

    try store.build_index();
    try store.build_filter(filter);
    try std.testing.expectEqual(2, store.len());

    {
        var slice = try store.at(0) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506729Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"hello\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    {
        var slice = try store.at(1) orelse @panic("no storage");
        defer slice.deinit();

        try std.testing.expectEqualSlices(
            u8,
            "{\"timestamp\":\"2024-03-14T00:55:51.506797Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"world\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}",
            slice.content() orelse @panic("no content"),
        );
    }

    try std.testing.expectEqual(null, try store.at(2));
}
