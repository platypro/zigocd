const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xml_dep = b.dependency("xml", .{});
    var xml_mod = xml_dep.module("xml");
    xml_mod.optimize = .ReleaseFast;
    const header_gen_mod = b.addModule("header_gen", .{ .root_source_file = b.path("src/root.zig") });
    header_gen_mod.addImport("xml", xml_mod);

    const exe = b.addExecutable(.{
        .name = "header_gen",
        .root_source_file = b.path("tool/main.zig"),
        .target = target,
        .optimize = optimize,
        .use_lld = false,
        .use_llvm = false,
    });

    exe.root_module.addImport("header_gen", header_gen_mod);
    b.installArtifact(exe);
}
