const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ocd = b.dependency("zigocd", .{}).module("ocd");
    const header_gen_module = b.dependency("header_gen", .{}).module("header_gen");

    const exe = b.addExecutable(.{ .name = "ocd", .root_source_file = b.path("interface/main.zig"), .optimize = optimize, .target = target });
    exe.root_module.addImport("ocd", ocd);
    exe.root_module.addImport("header_gen", header_gen_module);

    b.installArtifact(exe);

    //Test Firmware
    const test_firmware_dep = b.dependency("test_firmware", .{ });
    const test_firmware = test_firmware_dep.artifact("test_firmware.elf");

    b.installArtifact(test_firmware);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
