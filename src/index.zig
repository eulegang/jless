const std = @import("std");

const Error = std.os.MMapError || std.os.OpenError || std.mem.Allocator.Error;

pub const Entry = packed struct {
    index: u31,
    flag: bool,
};

const Index = struct {
    const Self = @This();

    valid: std.ArrayList(Entry),

    fn init(alloc: std.mem.Allocator) Self {
        const valid = std.ArrayList(Entry).init(alloc);

        return Self{
            .valid = valid,
        };
    }

    fn deinit(self: Self) void {
        self.valid.deinit();
    }
};

pub fn Page(comptime size: usize) type {
    return struct {
        const Self = @This();

        count: usize,
        base: [*]align(std.mem.page_size) u8,
        alloc: std.mem.Allocator,

        fn init(alloc: std.mem.Allocator, fd: std.os.fd_t, offset: usize) Error!*Self {
            var self = try alloc.create(Self);
            self.base = try std.os.mmap(null, size, std.os.PROT.READ, .{}, fd, offset);
            self.count = 1;
            self.alloc = alloc;
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

        pub fn init(file: []const u8, alloc: std.mem.Allocator) Error!*Store(size) {
            var self = try alloc.create(Self);
            errdefer alloc.destroy(self);

            self.fd = try std.os.open(file, .{ .ACCMODE = .RDONLY }, 0o644);
            errdefer std.os.close(self.fd);

            self.index = Index.init(alloc);

            return self;
        }

        fn page(self: *Self, offset: usize) Error!*Page(size) {
            Page(size).init(
                self.alloc,
                offset,
                self,
            );
        }

        pub fn deinit(self: *Self) void {
            self.index.deinit();
            std.os.close(self.fd);

            self.alloc.destroy(self);
        }

        pub fn build_index(self: *Self) !void {
            if (self.index.valid.items.len > 0) {
                self.index.valid.clearRetainingCapacity();
            }

            const st = try std.os.fstat(self.fd);
            _ = st.size;
        }

        pub fn view(self: *Self, base: usize, window: usize) [][]const u8 {
            _ = self;
            _ = base;
            _ = window;

            unreachable;
        }

        pub fn len(self: *Self) usize {
            return self.index.valid.items.len;
        }
    };
}
