const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_query = std.Target.Query{
        .abi = .eabihf,
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .ofmt = .elf,
        .os_tag = .freestanding,
    };

    const target = b.resolveTargetQuery(target_query);

    var exe = b.addExecutable(.{
        .name = "test_firmware.elf",
        .root_source_file = b.path("startup.zig"),
        .optimize = .Debug,
        .target = target,
    });
    exe.setLinkerScriptPath(b.path("test_firmware.ld"));

    b.installArtifact(exe);
}
