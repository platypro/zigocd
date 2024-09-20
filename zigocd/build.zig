const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ocd = b.addModule("ocd", .{ .root_source_file = b.path("root.zig") });

    // Link libusb
    const libusb_dep = b.dependency("libusb", .{});

    ocd.linkLibrary(libusb_dep.artifact("usb"));
    if (b.graph.host.result.os.tag == .windows) {
        ocd.linkSystemLibrary("shlwapi", .{});
    }

    // Generate Coresight IDs if changed
    const coresight_id_gen = b.addStaticLibrary(.{
        .name = "coresight_ids",
        .root_source_file = b.path("./API/SWD/product_ids.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.path("API/SWD/product_ids.csv").addStepDependencies(&coresight_id_gen.step);
    ocd.linkLibrary(coresight_id_gen);
}
