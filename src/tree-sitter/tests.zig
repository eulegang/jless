const std = @import("std");
const treesitter = @import("tree-sitter");

test "tree-sitter" {
    const ts = try treesitter.TS.init(.JSON);
    defer ts.deinit();

    const doc = "{\"nil\": null,\"number\":42,\"T\":true,\"F\":false,\"arr\":[true,false],\"str\":\"hello, world\",\"obj\":{\"n\":null}}";

    const tree = try ts.parse(doc, null);
    defer tree.deinit();

    {
        const q = try treesitter.Query.init(.JSON, "(pair key: (string) @capt)");
        defer q.deinit();

        const cursor = try treesitter.QueryCursor.init(q, tree.root());
        defer cursor.deinit();

        var r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"nil\"", doc[r.start..r.end]);

        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"number\"", doc[r.start..r.end]);

        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"T\"", doc[r.start..r.end]);

        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"F\"", doc[r.start..r.end]);

        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"arr\"", doc[r.start..r.end]);

        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"str\"", doc[r.start..r.end]);

        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"obj\"", doc[r.start..r.end]);

        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("\"n\"", doc[r.start..r.end]);

        try std.testing.expectEqual(null, cursor.next());
    }

    {
        const q = try treesitter.Query.init(.JSON, "[(true) (false) (null)] @capt");
        defer q.deinit();

        const cursor = try treesitter.QueryCursor.init(q, tree.root());
        defer cursor.deinit();

        var r = cursor.next().?.range();
        try std.testing.expectEqualStrings("null", doc[r.start..r.end]);
        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("true", doc[r.start..r.end]);
        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("false", doc[r.start..r.end]);
        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("true", doc[r.start..r.end]);
        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("false", doc[r.start..r.end]);
        r = cursor.next().?.range();
        try std.testing.expectEqualStrings("null", doc[r.start..r.end]);
        try std.testing.expectEqual(null, cursor.next());
    }
}
