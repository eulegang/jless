const std = @import("std");
const HVar = @import("../hvar.zig").HVar;

pub fn link(_: *std.Build.Step.Compile) void {}

pub fn linkStatic(b: *std.Build, prefix: []const u8, compile: *std.Build.Step.Compile) void {
    const p = b.fmt("{s}/lib/libonig.a", .{prefix});
    compile.addObjectFile(.{ .path = p });
}

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const onig = b.addStaticLibrary(.{
        .name = "oniguruma",
        .pic = true,
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });

    const wf = b.addWriteFile("config.h", HVar.fmt(b, &.{
        HVar{ .name = "HAVE_ALLOCA", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_ALLOCA_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_DLFCN_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_INTTYPES_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_MEMORY_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_STDINT_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_STDLIB_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_STRINGS_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_STRING_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_SYS_STAT_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_SYS_TIMES_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_SYS_TIME_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_SYS_TYPES_H", .value = .{ .number = 1 } },
        HVar{ .name = "HAVE_UNISTD_H", .value = .{ .number = 1 } },
        HVar{ .name = "LT_OBJDIR", .value = .{ .str = ".libs/" } },
        HVar{ .name = "PACKAGE", .value = .{ .str = "onig" } },
        HVar{ .name = "PACKAGE_BUGREPORT", .value = .{ .str = "" } },
        HVar{ .name = "PACKAGE_NAME", .value = .{ .str = "onig" } },
        HVar{ .name = "PACKAGE_STRING", .value = .{ .str = "onig 6.9.4" } },
        HVar{ .name = "PACKAGE_TARNAME", .value = .{ .str = "onig" } },
        HVar{ .name = "PACKAGE_URL", .value = .{ .str = "" } },
        HVar{ .name = "PACKAGE_VERSION", .value = .{ .str = "6.9.4" } },
        HVar{ .name = "SIZEOF_INT", .value = .{ .number = 4 } },
        HVar{ .name = "SIZEOF_LONG", .value = .{ .number = 8 } },
        HVar{ .name = "SIZEOF_LONG_LONG", .value = .{ .number = 8 } },
        HVar{ .name = "SIZEOF_VOIDP", .value = .{ .number = 8 } },
        HVar{ .name = "STDC_HEADERS", .value = .{ .number = 1 } },
        HVar{ .name = "VERSION", .value = .{ .str = "6.9.4" } },
    }) catch @panic(":P"));

    onig.addIncludePath(wf.getDirectory());
    onig.addIncludePath(.{ .path = "vender/jq/modules/oniguruma/src" });
    onig.addCSourceFiles(.{
        .root = .{ .path = "vender/jq/modules/oniguruma/" },
        .flags = &.{
            "-DUSE_POSIX_API",
            "-Wall",
            "-Wextra",
        },

        .files = &.{
            //"src/regint.h",
            //"src/regparse.h",
            //"src/regenc.h",
            //"src/st.h",
            "src/regerror.c",
            "src/regparse.c",
            "src/regext.c",
            "src/regcomp.c",
            "src/regexec.c",
            "src/reggnu.c",
            "src/regenc.c",
            "src/regsyntax.c",
            "src/regtrav.c",
            "src/regversion.c",
            "src/st.c",
            "src/onig_init.c",
            "src/unicode.c",
            "src/ascii.c",
            "src/utf8.c",
            "src/utf16_be.c",
            "src/utf16_le.c",
            "src/utf32_be.c",
            "src/utf32_le.c",
            "src/euc_jp.c",
            "src/sjis.c",
            "src/iso8859_1.c",
            "src/iso8859_2.c",
            "src/iso8859_3.c",
            "src/iso8859_4.c",
            "src/iso8859_5.c",
            "src/iso8859_6.c",
            "src/iso8859_7.c",
            "src/iso8859_8.c",
            "src/iso8859_9.c",
            "src/iso8859_10.c",
            "src/iso8859_11.c",
            "src/iso8859_13.c",
            "src/iso8859_14.c",
            "src/iso8859_15.c",
            "src/iso8859_16.c",
            "src/euc_tw.c",
            "src/euc_kr.c",
            "src/big5.c",
            "src/gb18030.c",
            "src/koi8_r.c",
            "src/cp1251.c",
            "src/euc_jp_prop.c",
            "src/sjis_prop.c",
            "src/unicode_unfold_key.c",
            "src/unicode_fold1_key.c",
            "src/unicode_fold2_key.c",
            "src/unicode_fold3_key.c",

            // Should really add option for these
            "src/regposix.c",
            "src/regposerr.c",
        },
    });

    return onig;
}
