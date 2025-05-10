const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_query = std.Target.Query{
        .abi = .eabihf,
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .ofmt = .elf,
        .os_tag = .freestanding,
    };

    const header_gen = b.dependency("header_gen", .{});
    const target = b.resolveTargetQuery(target_query);

    const header_gen_run = b.addRunArtifact(header_gen.artifact("header_gen"));
    _ = header_gen_run;
    //  header_gen_run.addArg(arg: []const u8)

    var exe = b.addExecutable(.{
        .name = "test_firmware.elf",
        .root_source_file = b.path("startup.zig"),
        .optimize = .ReleaseFast,
        .target = target,
    });
    exe.setLinkerScript(b.path("test_firmware.ld"));

    b.installArtifact(exe);
}
