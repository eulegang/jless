const std = @import("std");
const JQ = @import("jq").JQ;

test "projection" {
    const jq = try JQ.init("{subject: .subject}", std.testing.allocator);
    defer jq.deinit();

    var out = try jq.project("{\"subject\": \"world\", \"greeting\": \"hello\"}");
    try std.testing.expectEqualSlices(u8, out, "{\"subject\":\"world\"}");

    out = try jq.project("{\"timestamp\":\"2024-03-14T00:55:51.506729Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"hello\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}");
}

test "multi projection" {
    const jq = try JQ.init("{level: .level}", std.testing.allocator);
    defer jq.deinit();

    var out = try jq.project("{\"timestamp\":\"2024-03-14T00:55:51.506729Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"hello\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}");
    try std.testing.expectEqualSlices(u8, out, "{\"level\":\"INFO\"}");

    out = try jq.project("{\"timestamp\":\"2024-03-14T00:55:51.506797Z\",\"level\":\"INFO\",\"fields\":{\"message\":\"world\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}");
    try std.testing.expectEqualSlices(u8, out, "{\"level\":\"INFO\"}");

    out = try jq.project("{\"timestamp\":\"2024-03-14T00:55:51.506811Z\",\"level\":\"WARN\",\"fields\":{\"message\":\"do well\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}");
    try std.testing.expectEqualSlices(u8, out, "{\"level\":\"WARN\"}");

    out = try jq.project("{\"timestamp\":\"2024-03-14T00:55:51.506824Z\",\"level\":\"DEBUG\",\"fields\":{\"message\":\"often\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}");
    try std.testing.expectEqualSlices(u8, out, "{\"level\":\"DEBUG\"}");

    out = try jq.project("{\"timestamp\":\"2024-03-14T00:55:51.506836Z\",\"level\":\"TRACE\",\"fields\":{\"message\":\"never\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}");
    try std.testing.expectEqualSlices(u8, out, "{\"level\":\"TRACE\"}");

    out = try jq.project("{\"timestamp\":\"2024-03-14T00:55:51.506847Z\",\"level\":\"ERROR\",\"fields\":{\"message\":\"is to human\"},\"target\":\"sample_builder\",\"filename\":\"src/main.rs\"}");
    try std.testing.expectEqualSlices(u8, out, "{\"level\":\"ERROR\"}");
}
