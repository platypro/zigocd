const std = @import("std");

const libcxmdb = @import("libcxmdb");
const ElfDecoder = @import("ElfDecoder.zig");

const Error = error{
    NoDevice,
};

fn printCoresightItem(component: libcxmdb.API.getClass(.swd).Component) void {
    switch (component.data) {
        .ROMTABLE => {
            for (component.data.ROMTABLE.entries.items) |item| {
                std.debug.print(
                    "Romtable Entry PRESENT:{x} FORMAT:{x} POWERIDVALID:{x} POWERID:{x} OFFSET:{x}\n",
                    .{ item.entry.PRESENT, item.entry.FORMAT, item.entry.POWERIDVALID, item.entry.POWERID, item.entry.OFFSET },
                );

                printCoresightItem(item.component);
            }
        },
        .CORESIGHT_COMPONENT => {
            std.debug.print("Coresight\n", .{});
        },
        else => {
            std.debug.print("Unknown Type\n", .{});
        },
    }
}

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
        std.debug.print("Name: {s}, Start addr: {x}, End Addr:{x}\n", .{ loadable_section.name, loadable_section.start_addr, loadable_section.end_addr });
    }

    std.debug.print("\nPrograms (Virtual Memory to Target Memory Mappings)\n", .{});
    for (elf_file.load_maps.items) |load_map| {
        std.debug.print("VMA:{x}, LMA:{x}, Size:{x}\n", .{ load_map.vma, load_map.lma, load_map.size });
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

    const aps = try libcxmdb.API.getClass(.swd).probe(swd);

    for (aps.items, 0..) |ap, i| {
        std.debug.print(
            "AP {x} TYPE:{x} VARIANT:{x} CLASS:{x} DESIGNER:{x}, REVISION:{x}\n",
            .{ i, ap.idr.TYPE, ap.idr.VARIANT, ap.idr.CLASS, ap.idr.DESIGNER, ap.idr.REVISION },
        );

        std.debug.print("Component (Base {x})\n", .{@as(u32, @intCast(ap.component.base_address)) << 12});
        printCoresightItem(ap.component);
    }

    // try libcxmdb.Node.getClass(.samd51).connect(samd51);
}
