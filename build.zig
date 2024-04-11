const std = @import("std");

const Linkage = enum {
    Dynamic,
    Static,
    Vendered,

    fn link(self: @This(), compile: *std.Build.Step.Compile) void {
        switch (self) {
            .Dynamic => {
                compile.addIncludePath(.{ .path = "/usr/local/include/" });
                compile.addRPath(.{ .path = "/usr/local/lib" });

                compile.linkSystemLibrary("jq");
                compile.linkSystemLibrary("tree-sitter");
                compile.linkSystemLibrary("tree-sitter-json");
                compile.linkSystemLibrary("tree-sitter-jq");

                compile.linkLibC();
            },

            .Static => {
                compile.addIncludePath(.{ .path = "/usr/local/include/" });
                compile.addRPath(.{ .path = "/usr/local/lib" });

                compile.addObjectFile(.{ .path = "/usr/local/lib/libjq.a" });
                compile.addObjectFile(.{ .path = "/usr/local/lib/libonig.a" });
                compile.addObjectFile(.{ .path = "/usr/local/lib/libtree-sitter.a" });
                compile.addObjectFile(.{ .path = "/usr/local/lib/libtree-sitter-json.a" });
                compile.addObjectFile(.{ .path = "/usr/local/lib/libtree-sitter-jq.a" });

                compile.linkLibC();
            },

            .Vendered => @panic("vendered is currently not supported"),
        }
    }
};

pub fn build_tree_sitter_vendered(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
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

pub fn build_tree_sitter_json_vendered(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "tree-sitter-json",
        .pic = true,
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });

    lib.addIncludePath(.{ .path = "vender/tree-sitter-json/src/" });

    lib.addCSourceFiles(.{
        .root = .{ .path = "vender/tree-sitter-json/" },
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

pub fn build_tree_sitter_jq_vendered(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const static = b.option(bool, "static", "build a statically linked executable") orelse false;
    //const vendored = b.option(bool, "vendored", "build a statically linked with default dependency sources ") orelse false;

    const tree_sitter_vendered = build_tree_sitter_vendered(b, target, optimize);
    const tree_sitter_json_vendered = build_tree_sitter_json_vendered(b, target, optimize);
    const tree_sitter_jq_vendered = build_tree_sitter_jq_vendered(b, target, optimize);

    var linkage = Linkage.Dynamic;

    if (static) {
        linkage = Linkage.Static;
    }

    const exe = b.addExecutable(.{
        .name = "jless",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const cli = b.dependency("zig-cli", .{
        .target = target,
        .optimize = optimize,
    });

    const mirror = b.dependency("mirror", .{
        .target = target,
        .optimize = optimize,
    });

    const ts_mod = b.createModule(.{
        .root_source_file = .{ .path = "src/tree-sitter/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const render_mod = b.createModule(.{
        .root_source_file = .{ .path = "src/render/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const jq_mod = b.createModule(.{
        .root_source_file = .{ .path = "src/jq/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zig-cli", cli.module("zig-cli"));
    exe.root_module.addImport("mirror", mirror.module("mirror"));
    exe.root_module.addImport("tree-sitter", ts_mod);
    exe.root_module.addImport("render", render_mod);
    exe.root_module.addImport("jq", jq_mod);

    linkage.link(exe);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    b.installArtifact(tree_sitter_vendered);
    b.installArtifact(tree_sitter_json_vendered);
    b.installArtifact(tree_sitter_jq_vendered);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    var runs = std.ArrayList(*std.Build.Step.Run).init(b.allocator);
    const tests_files: [8][]const u8 = .{
        "src/main.zig",
        "src/index.zig",
        "src/theme.zig",
        "src/jsonp.zig",
        "src/highlighter.zig",

        "src/jq/main.zig",
        "src/tree-sitter/tests.zig",
        "src/render/tests.zig",
    };

    for (tests_files) |file| {
        const tests = b.addTest(.{
            .root_source_file = .{ .path = file },
            .target = target,
            .optimize = optimize,
        });

        linkage.link(tests);

        tests.root_module.addImport("tree-sitter", ts_mod);
        tests.root_module.addImport("render", render_mod);
        tests.root_module.addImport("jq", jq_mod);

        runs.append(b.addRunArtifact(tests)) catch unreachable;
    }

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    for (runs.items) |run| {
        test_step.dependOn(&run.step);
    }
}
