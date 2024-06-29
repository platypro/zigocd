const std = @import("std");
const DeviceConnection = @import("DeviceConnection.zig");

const Error = error{
    NoDevice,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var connection = try DeviceConnection.init(allocator);
    const devices = try connection.get_devices();

    for (devices) |device| {
        std.debug.print("Device Found: {s} {s}\n", .{ device.manufacturer_str, device.product_str });
    }

    connection.deinit();
}
