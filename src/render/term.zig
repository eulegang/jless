const std = @import("std");
const tag = @import("builtin").os.tag;

/// Manages the termios for various platforms
pub const Term = struct {
    term: std.os.termios,

    pub fn init() Term {
        var term: std.os.termios = undefined;

        switch (tag) {
            .linux => _ = std.os.linux.tcgetattr(1, &term),
            .macos => _ = std.os.darwin.tcgetattr(1, &term),

            else => @compileError("not supported"),
        }

        return Term{ .term = term };
    }

    pub fn raw(self: Term) void {
        switch (tag) {
            .linux => {
                var mod = self.term;

                mod.lflag.ECHO = false;
                mod.lflag.ICANON = false;
                mod.lflag.ISIG = false;
                mod.lflag.IEXTEN = false;

                mod.oflag.OPOST = false;

                mod.iflag.IXON = false;
                mod.iflag.BRKINT = false;
                mod.iflag.INPCK = false;
                mod.iflag.ISTRIP = false;

                _ = std.os.linux.tcsetattr(1, .FLUSH, &mod);
            },

            else => {},
        }
    }

    pub fn deinit(self: Term) void {
        switch (tag) {
            .linux => {
                _ = std.os.linux.tcsetattr(1, .FLUSH, &self.term);
            },

            else => {},
        }
    }
};
