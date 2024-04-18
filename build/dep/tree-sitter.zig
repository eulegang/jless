const std = @import("std");

pub fn link(compile: *std.Build.Step.Compile) void {
    compile.linkSystemLibrary("tree-sitter");
}

pub fn linkStatic(b: *std.Build, prefix: []const u8, compile: *std.Build.Step.Compile) void {
    const p = b.fmt("{s}/lib/libtree-sitter.a", .{prefix});
    compile.addObjectFile(.{ .path = p });
}

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "tree-sitter",
        .pic = true,
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });

    lib.addIncludePath(.{ .path = "vender/tree-sitter/lib/src" });
    lib.addIncludePath(.{ .path = "vender/tree-sitter/lib/src/wasm" });
    lib.addIncludePath(.{ .path = "vender/tree-sitter/lib/include" });

    lib.addCSourceFiles(.{
        .root = .{ .path = "vender/tree-sitter/" },
        .files = &.{
            "lib/src/alloc.c",
            "lib/src/get_changed_ranges.c",
            "lib/src/language.c",
            "lib/src/lexer.c",
            "lib/src/node.c",
            "lib/src/parser.c",
            "lib/src/query.c",
            "lib/src/stack.c",
            "lib/src/subtree.c",
            "lib/src/tree.c",
            "lib/src/tree_cursor.c",
            "lib/src/wasm_store.c",
        },
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-Wshadow",
            "-pedantic",
            "-fPIC",
            "-fvisibility=hidden",
            "-std=c11",
        },
    });

    return lib;
}
