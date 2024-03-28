const std = @import("std");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

pub extern "c" fn tree_sitter_json() ?*c.TSLanguage;

pub const Error = error{
    InvalidParser,
    InvalidLang,
    InvalidCursor,
    InvalidQuery,
    Parse,
};

pub const Range = struct {
    start: usize,
    end: usize,
};

pub const Node = struct {
    node: c.TSNode,

    pub fn range(self: Node) Range {
        const start = c.ts_node_start_byte(self.node);
        const end = c.ts_node_end_byte(self.node);

        return Range{
            .start = start,
            .end = end,
        };
    }
};

pub const Tree = struct {
    tree: *c.TSTree,

    pub fn root(self: Tree) Node {
        return Node{ .node = c.ts_tree_root_node(self.tree) };
    }

    pub fn deinit(self: Tree) void {
        c.ts_tree_delete(self.tree);
    }
};

pub const TS = struct {
    parser: *c.TSParser,

    pub fn json() Error!TS {
        const parser = c.ts_parser_new() orelse return Error.InvalidParser;

        if (!c.ts_parser_set_language(parser, tree_sitter_json())) {
            return Error.InvalidLang;
        }

        return TS{ .parser = parser };
    }

    pub fn deinit(self: TS) void {
        c.ts_parser_delete(self.parser);
    }

    pub fn parse(self: TS, buf: []const u8) Error!Tree {
        const tree = c.ts_parser_parse_string(self.parser, null, buf.ptr, @intCast(buf.len)) orelse return Error.Parse;

        return Tree{ .tree = tree };
    }
};

const QueryError = error{
    QueryAlloc,
    QuerySyntax,
    QueryNodeType,
    QueryField,
    QueryCapture,
};

pub const Query = struct {
    query: *c.TSQuery,

    pub fn json(parse: []const u8) QueryError!Query {
        var err: u32 = 0;
        var off: u32 = 0;
        const query = c.ts_query_new(tree_sitter_json(), parse.ptr, @intCast(parse.len), &off, &err) orelse return QueryError.QueryAlloc;

        switch (err) {
            0 => {},
            1 => return QueryError.QuerySyntax,
            2 => return QueryError.QueryNodeType,
            3 => return QueryError.QueryField,
            4 => return QueryError.QueryCapture,
            else => @panic("Invalid error found"),
        }

        return Query{ .query = query };
    }

    pub fn deinit(self: Query) void {
        c.ts_query_delete(self.query);
    }
};

pub const Match = struct {};

pub const QueryCursor = struct {
    cursor: *c.TSQueryCursor,

    pub fn init(query: Query, node: Node) !QueryCursor {
        const cursor = c.ts_query_cursor_new() orelse return Error.InvalidCursor;

        c.ts_query_cursor_exec(cursor, query.query, node.node);

        return QueryCursor{ .cursor = cursor };
    }

    pub fn deinit(self: QueryCursor) void {
        c.ts_query_cursor_delete(self.cursor);
    }

    pub fn next(self: QueryCursor) ?Node {
        var match: c.TSQueryMatch = undefined;
        if (c.ts_query_cursor_next_match(self.cursor, &match)) {
            if (match.capture_count == 0) {
                return null;
            }

            return Node{ .node = match.captures.*.node };
        } else {
            return null;
        }
    }
};

test "tree-sitter" {
    const ts = try TS.json();
    defer ts.deinit();

    const doc = "{\"nil\": null,\"number\":42,\"T\":true,\"F\":false,\"arr\":[true,false],\"str\":\"hello, world\",\"obj\":{\"n\":null}}";

    const tree = try ts.parse(doc);
    defer tree.deinit();

    {
        const q = try Query.json("(pair key: (string) @capt)");
        defer q.deinit();

        const cursor = try QueryCursor.init(q, tree.root());
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
        const q = try Query.json("[(true) (false) (null)] @capt");
        defer q.deinit();

        const cursor = try QueryCursor.init(q, tree.root());
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
