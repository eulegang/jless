const std = @import("std");

const dep_jq = @import("build/dep/jq.zig");
const dep_ts = @import("build/dep/tree-sitter.zig");
const dep_ts_json = @import("build/dep/tree-sitter-json.zig");
const dep_ts_jq = @import("build/dep/tree-sitter-jq.zig");
const dep_onig = @import("build/dep/oniguruma.zig");

const XTarget = struct {
    name: []const u8,
    target: std.Build.ResolvedTarget,
};

const Linkage = enum {
    Dynamic,
    Static,
    Vendered,

    fn link(self: @This(), b: *std.Build, prefix: []const u8, compile: *std.Build.Step.Compile) void {
        switch (self) {
            .Dynamic => {
                compile.addIncludePath(.{ .path = b.fmt("{s}/lib", .{prefix}) });
                compile.addRPath(.{ .path = b.fmt("{s}/lib", .{prefix}) });

                dep_jq.link(compile);
                dep_ts.link(compile);
                dep_ts_json.link(compile);
                dep_ts_jq.link(compile);

                compile.linkLibC();
            },

            .Static => {
                compile.addIncludePath(.{ .path = "/usr/local/include/" });

                dep_jq.linkStatic(b, prefix, compile);
                dep_ts.linkStatic(b, prefix, compile);
                dep_ts_json.linkStatic(b, prefix, compile);
                dep_ts_jq.linkStatic(b, prefix, compile);
                dep_onig.linkStatic(b, prefix, compile);

                compile.linkLibC();
            },

            .Vendered => @panic("vendered is currently not supported"),
        }
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const static = b.option(bool, "static", "build a statically linked executable") orelse false;
    const prefix = b.option([]const u8, "prefix", "prefix for linking libraries") orelse "/usr/local/";

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

    linkage.link(b, prefix, exe);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);
    //b.installArtifact(tree_sitter_vendered);
    //b.installArtifact(tree_sitter_json_vendered);
    //b.installArtifact(tree_sitter_jq_vendered);
    //b.installArtifact(onig_vendered);

    const xinstall_step = b.step("xinstall", "install supported os/archs");

    const targets: []const XTarget = &.{
        .{
            .name = "darwin-aarch64",
            .target = b.resolveTargetQuery(.{ .os_tag = .macos, .cpu_arch = .aarch64 }),
        },
        .{
            .name = "darwin-x86_64",
            .target = b.resolveTargetQuery(.{ .os_tag = .macos, .cpu_arch = .x86_64 }),
        },
        .{
            .name = "linux-x86_64",
            .target = b.resolveTargetQuery(.{ .os_tag = .linux, .cpu_arch = .x86_64 }),
        },
        .{
            .name = "linux-aarch64",
            .target = b.resolveTargetQuery(.{ .os_tag = .linux, .cpu_arch = .aarch64 }),
        },
    };

    for (targets) |t| {
        cross_install(b, xinstall_step, t);
    }

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

        linkage.link(b, prefix, tests);

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

fn cross_install(b: *std.Build, step: *std.Build.Step, t: XTarget) void {
    const name = b.fmt("jless-{s}", .{t.name});
    const target = t.target;
    const optimize = std.builtin.OptimizeMode.ReleaseFast;

    const exe = b.addExecutable(.{
        .name = name,
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

    ts_mod.addIncludePath(.{ .path = "vender/tree-sitter/lib/include" });

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

    jq_mod.addIncludePath(.{ .path = "vender/jq/src/" });

    exe.root_module.addImport("zig-cli", cli.module("zig-cli"));
    exe.root_module.addImport("mirror", mirror.module("mirror"));
    exe.root_module.addImport("tree-sitter", ts_mod);
    exe.root_module.addImport("render", render_mod);
    exe.root_module.addImport("jq", jq_mod);

    exe.linkLibrary(dep_ts.build(b, target, optimize));
    exe.linkLibrary(dep_ts_json.build(b, target, optimize));
    exe.linkLibrary(dep_ts_jq.build(b, target, optimize));

    exe.linkLibrary(dep_onig.build(b, target, optimize));
    exe.linkLibrary(dep_jq.build(b, target, optimize));

    const install = b.addInstallArtifact(exe, .{});

    step.dependOn(&install.step);
}
