const std = @import("std");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});

const log = std.log.scoped(.treesitter);

pub extern "c" fn tree_sitter_json() ?*c.TSLanguage;
pub extern "c" fn tree_sitter_jq() ?*c.TSLanguage;

pub const Lang = enum {
    JSON,
    JQ,

    fn lang(self: @This()) ?*c.TSLanguage {
        return switch (self) {
            .JSON => tree_sitter_json(),
            .JQ => tree_sitter_jq(),
        };
    }
};

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

pub const InputEdit = c.TSInputEdit;

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

    pub fn has_error(self: Node) bool {
        return c.ts_node_has_error(self.node);
    }
};

pub const Tree = struct {
    tree: *c.TSTree,

    pub fn root(self: Tree) Node {
        return Node{ .node = c.ts_tree_root_node(self.tree) };
    }

    pub fn edit(self: Tree, input_edit: InputEdit) void {
        c.ts_tree_edit(self.tree, &input_edit);
    }

    pub fn deinit(self: Tree) void {
        c.ts_tree_delete(self.tree);
    }
};

pub const TS = struct {
    parser: *c.TSParser,

    pub fn init(lang: Lang) Error!TS {
        const parser = c.ts_parser_new() orelse return Error.InvalidParser;

        const l = lang.lang();

        if (!c.ts_parser_set_language(parser, l)) {
            return Error.InvalidLang;
        }

        return TS{ .parser = parser };
    }

    pub fn deinit(self: TS) void {
        c.ts_parser_delete(self.parser);
    }

    pub fn parse(self: TS, buf: []const u8, old: ?Tree) Error!Tree {
        log.debug("parsing buffer", .{ .buffer = buf });
        var old_tree: ?*c.TSTree = null;
        if (old) |o| {
            old_tree = o.tree;
        }

        const tree = c.ts_parser_parse_string(self.parser, old_tree, buf.ptr, @intCast(buf.len)) orelse return Error.Parse;

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

    pub fn init(lang: Lang, parse: []const u8) QueryError!Query {
        var err: u32 = 0;
        var off: u32 = 0;
        const query = c.ts_query_new(lang.lang(), parse.ptr, @intCast(parse.len), &off, &err) orelse return QueryError.QueryAlloc;

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
