const std = @import("std");

pub fn link(compile: *std.Build.Step.Compile) void {
    compile.linkSystemLibrary("tree-sitter-jq");
}

pub fn linkStatic(b: *std.Build, prefix: []const u8, compile: *std.Build.Step.Compile) void {
    const p = b.fmt("{s}/lib/libtree-sitter-jq.a", .{prefix});
    compile.addObjectFile(.{ .path = p });
}

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "tree-sitter-jq",
        .pic = true,
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });

    lib.addIncludePath(.{ .path = "vender/tree-sitter-jq/src/" });

    lib.addCSourceFiles(.{
        .root = .{ .path = "vender/tree-sitter-jq/" },
        .files = &.{
            "src/parser.c",
        },
        .flags = &.{
            "-Wall",
            "-Wextra",
            "-std=gnu99",
        },
    });

    return lib;
}
