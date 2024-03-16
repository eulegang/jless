const std = @import("std");
const JQ = @import("jq.zig").JQ;

const Inputs = @import("inputs.zig").Inputs;
const Term = @import("term.zig").Term;

pub const System = struct {
    inputs: Inputs,
    term: Term,

    filter: ?JQ,

    pub fn init(file: ?[]const u8) !System {
        const inputs = try Inputs.init(file);
        const term = Term.init();

        return System{
            .inputs = inputs,
            .term = term,
            .filter = null,
        };
    }

    pub fn setup(self: *@This()) !void {
        self.term.raw();
    }

    pub fn tick(self: *@This()) !bool {
        const event = try self.inputs.event();
        switch (event) {
            .line => |line| {
                std.debug.print("line \"{s}\"\r\n", .{line});
            },

            .input => |input| {
                std.debug.print("event {}\r\n", .{input});

                if (input == .Quit) {
                    return false;
                }
            },
        }

        return true;
    }

    pub fn close(self: *@This()) void {
        self.inputs.close();
        self.term.deinit();
    }
};
