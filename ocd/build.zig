const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const renderer_mod = b.addModule("renderer", .{ .root_source_file = b.path("src/Renderer.zig") });

    const ocd = b.addModule("ocd", .{ .root_source_file = b.path("src/root.zig") });
    ocd.addImport("renderer", renderer_mod);

    // Link libusb
    const libusb_dep = b.dependency("libusb", .{});

    ocd.linkLibrary(libusb_dep.artifact("usb"));
    if (b.graph.host.result.os.tag == .windows) {
        ocd.linkSystemLibrary("shlwapi", .{});
    }

    // Generate Coresight IDs if changed
    const coresight_id_exe = b.addExecutable(.{
        .name = "coresight_id_generator",
        .root_source_file = b.path("./src/API/SWD/product_ids.zig"),
        .target = target,
        .optimize = optimize,
    });

    coresight_id_exe.root_module.addImport("renderer", renderer_mod);

    const coresight_id_gen = b.addRunArtifact(coresight_id_exe);
    coresight_id_gen.addFileArg(b.path("./src/API/SWD/product_ids.csv"));
    const coresight_id_zig = coresight_id_gen.addOutputFileArg("product_ids_gen.zig");
    b.path("API/SWD/product_ids.csv").addStepDependencies(&coresight_id_gen.step);

    const coresight_id_mod = b.addModule("coresight_ids", .{ .root_source_file = coresight_id_zig });
    ocd.addImport("coresight_ids", coresight_id_mod);
}
