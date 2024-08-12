const std = @import("std");

const libcxmdb = @import("libcxmdb");
const ElfDecoder = @import("ElfDecoder.zig");

// pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
//     @breakpoint();
//     std.builtin.default_panic(msg, error_return_trace, ret_addr);
// }

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

    var elf_file = try ElfDecoder.load(allocator, elf_path);
    defer elf_file.close();

    std.debug.print("Sections (Virtual Memory)\n", .{});

    for (elf_file.loadable_sections.items) |loadable_section| {
        std.debug.print("Name: {s}, Start addr: {}, End Addr:{}\n", .{ loadable_section.name, loadable_section.start_addr, loadable_section.end_addr });
    }

    std.debug.print("\nPrograms (Virtual Memory to Target Memory Mappings)\n", .{});
    for (elf_file.load_maps.items) |load_map| {
        std.debug.print("VMA:{}, LMA:{}, Size:{}\n", .{ load_map.vma, load_map.lma, load_map.size });
    }

    var debugger: libcxmdb = undefined;
    try debugger.init(allocator);
    defer debugger.deinit();

    const node = debugger.getRootNode();
    const usb = try node.getApi(.usb);
    const jlink = try debugger.spawnNode(.jlink);
    jlink.transport = usb;

    const swd = try jlink.getApi(.swd);
    const samd51 = try debugger.spawnNode(.samd51);
    samd51.transport = swd;

    try libcxmdb.Node.getClass(.jlink).connect_to_first(jlink);

    // This will go into samd51 eventually
    try libcxmdb.API.getClass(.swd).setup_connection(swd);

    //node.

    // var connection = try DeviceConnection.init(allocator);
    // defer connection.deinit();
    // const devices = try connection.get_devices();

    // if (devices.len == 0) {
    //     std.debug.print("No Devices!\n", .{});
    //     return;
    // }

    // var dev_promise = try connection.choose_device(devices[0]);
    // _ = try dev_promise.wait();

    _ = try libcxmdb.API.getClass(.swd).query_aps(swd);
}
