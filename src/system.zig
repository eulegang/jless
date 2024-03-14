const std = @import("std");
const tag = @import("builtin").os.tag;

const Inputs = @import("inputs.zig").Inputs;

pub const System = struct {
    inputs: Inputs,
    term: std.os.termios,

    pub fn init(file: ?[]const u8, allocator: std.mem.Allocator) !System {
        const inputs = try Inputs.init(file, allocator);

        return System{
            .inputs = inputs,
            .term = undefined,
        };
    }

    pub fn setup(self: *@This()) !void {
        switch (tag) {
            .linux => {
                _ = std.os.linux.tcgetattr(1, &self.term);
                var term = self.term;

                term.lflag.ECHO = false;
                term.lflag.ICANON = false;
                term.lflag.ISIG = false;
                term.lflag.IEXTEN = false;

                term.oflag.OPOST = false;

                term.iflag.IXON = false;
                term.iflag.BRKINT = false;
                term.iflag.INPCK = false;
                term.iflag.ISTRIP = false;

                _ = std.os.linux.tcsetattr(1, .FLUSH, &term);
            },

            else => {},
        }
    }

    pub fn tick(self: *@This()) !bool {
        _ = try std.os.write(1, "tick\r\n");
        const event = try self.inputs.event();
        switch (event) {
            .line => |line| {
                _ = line;

                _ = try std.os.write(1, "line\r\n");
            },

            .input => |input| {
                switch (input) {
                    .Up => {
                        _ = try std.os.write(1, "up\r\n");
                    },
                    .Down => {
                        _ = try std.os.write(1, "down\r\n");
                    },
                    .Select => {
                        _ = try std.os.write(1, "select\r\n");
                    },

                    .Quit => {
                        _ = try std.os.write(1, "quit\r\n");
                        return false;
                    },
                }
            },
        }

        return true;
    }

    pub fn close(self: *@This()) void {
        self.inputs.close();

        switch (tag) {
            .linux => {
                _ = std.os.linux.tcsetattr(1, .FLUSH, &self.term);
            },

            else => {},
        }
    }
};
