const std = @import("std");
const DeviceConnection = @import("DeviceConnection.zig");
const ElfDecoder = @import("ElfDecoder.zig");

const Error = error{
    NoDevice,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const exepath = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exepath);
    const elf_path = try std.fs.path.join(allocator, &.{ exepath, "test_firmware.elf" });
    defer allocator.free(elf_path);

    const elf_file = try ElfDecoder.load(elf_path);
    defer elf_file.close();

    var connection = try DeviceConnection.init(allocator);
    const devices = try connection.get_devices();

    for (devices) |device| {
        std.debug.print("Device Found: {s} {s}\n", .{ device.manufacturer_str, device.product_str });
    }

    connection.deinit();
}
