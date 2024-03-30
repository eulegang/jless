const std = @import("std");
const render = @import("render");

test "moving cursor" {
    var r = render.test_instance;

    try r.move_cursor(0, 0);
    try r.move_cursor(10, 10);

    try std.testing.expectEqualSlices(u8, "\x1b[1;0H\x1b[11;10H", r.buffer[0..r.cur]);
}
