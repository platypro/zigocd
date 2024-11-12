const definitions = @import("definitions.zig");

const std = @import("std");
const ocd = @import("../../root.zig");
const SWD = @import("../SWD.zig");

const coresight_ids = @import("coresight_ids");
const CoresightEntry = struct { definitions.AP };

const Error = error{
    Recursion,
};

const RomtableProcessedEntry = struct {
    entry: definitions.ROMTABLE_ROMENTRY,
    component: Component,
};

pub const Component = struct {
    base_address: u32,
    manufacturer: u16,
    product: u16,
    revision: u16,
    revision_minor: u16,
    customer_modified: bool,
    name: []const u8,
    data: union(definitions.CORESIGHT_CLASS) {
        GENERIC: void,
        ROMTABLE: struct {
            entries: std.ArrayList(RomtableProcessedEntry),
        },
        CORESIGHT_COMPONENT: struct {
            arch: definitions.CORESIGHT_DEVARCH,
        },
        PERIPHERAL_TEST_BLOCK: void,
        GENERIC_IP_COMPONENT: void,
        OTHER: usize,
    },
};

const APDefinition = struct {
    idr: definitions.AP_IDR,
    component: Component,
};

pub fn read_coresight_register(self: *ocd.API, base: u32, Reg: type) !Reg {
    const val = try SWD.read_mem_single(self, base + Reg.addr);
    return SWD.u32ToStruct(Reg, val);
}

pub fn write_coresight_register(self: *ocd.API, base: u32, reg: anytype) void {
    const val: u32 = SWD.structToU32(reg);
    _ = SWD.write_mem(self, base + reg.addr, &val);
}

fn lookup_product(manufacturer: u16, product: u16) []const u8 {
    for (coresight_ids.ids) |id| {
        if (id.manufacturer == manufacturer and id.product == product) {
            return id.name;
        }
    }
    return "Unknown Device";
}

fn probe_coresight_element(self: *ocd.API, base: u32, depth: u32) !Component {
    if (depth > 2) {
        return Error.Recursion;
    }

    // Read idr registers
    var idr_regs: [12]u32 = undefined;
    _ = try SWD.read_mem(self, base + 0xFD0, &idr_regs);

    const cidr1 = try SWD.u32ToStruct(definitions.CORESIGHT_CIDR1, idr_regs[9]);
    const pidr0 = try SWD.u32ToStruct(definitions.CORESIGHT_PIDR0, idr_regs[4]);
    const pidr1 = try SWD.u32ToStruct(definitions.CORESIGHT_PIDR1, idr_regs[5]);
    const pidr2 = try SWD.u32ToStruct(definitions.CORESIGHT_PIDR2, idr_regs[6]);
    const pidr3 = try SWD.u32ToStruct(definitions.CORESIGHT_PIDR3, idr_regs[7]);
    const pidr4 = try SWD.u32ToStruct(definitions.CORESIGHT_PIDR4, idr_regs[0]);
    var result: Component = undefined;

    const manufacturer: u16 = (@as(u16, @intCast(pidr4.DES_2)) << 7) | (@as(u16, @intCast(pidr2.DES_1)) << 4) | @as(u16, @intCast(pidr1.DES_0));
    result.manufacturer = manufacturer;
    result.product = @as(u16, @intCast(pidr1.PART_1)) << 8 | @as(u16, @intCast(pidr0.PART_0));
    result.revision = @intCast(pidr2.REVISION);
    result.customer_modified = (pidr3.CMOD != 0);
    result.revision_minor = @intCast(pidr3.REVAND);
    result.name = lookup_product(result.manufacturer, result.product);
    result.base_address = base;
    switch (cidr1.CLASS) {
        .GENERIC => {
            result.data = .{ .GENERIC = {} };
        },
        .ROMTABLE => {
            var current_addr = base;
            result.data = .{ .ROMTABLE = .{ .entries = std.ArrayList(RomtableProcessedEntry).init(self.allocator) } };
            for (0..10) |_| {
                const entry = try SWD.read_mem_single(self, current_addr);
                current_addr += 4;

                if (entry == 0) {
                    break;
                }

                const entry_raw = try SWD.u32ToStruct(definitions.ROMTABLE_ROMENTRY, entry);
                if (entry_raw.PRESENT == 0) continue;

                var processed_entry = try result.data.ROMTABLE.entries.addOne();
                processed_entry.entry = entry_raw;

                var offset: u32 = @intCast(processed_entry.entry.OFFSET);
                offset <<= 12;

                processed_entry.component = try probe_coresight_element(self, @addWithOverflow(base, offset)[0], depth + 1);
            }
        },
        .CORESIGHT_COMPONENT => {
            result.data = .{ .CORESIGHT_COMPONENT = .{ .arch = try read_coresight_register(self, base, definitions.CORESIGHT_DEVARCH) } };
        },
        .PERIPHERAL_TEST_BLOCK => {
            result.data = .{ .PERIPHERAL_TEST_BLOCK = {} };
        },
        .GENERIC_IP_COMPONENT => {
            result.data = .{ .GENERIC_IP_COMPONENT = {} };
        },
        else => {
            result.data = .{ .OTHER = @intFromEnum(cidr1.CLASS) };
        },
    }

    return result;
}

pub fn probe(self: *ocd.API) !std.ArrayList(APDefinition) {
    try SWD.setup_connection(self);
    // const result = std.ArrayList(APDefinition).init(self.allocator);
    var aps: std.ArrayList(definitions.AP_IDR) = try SWD.query_aps(self);
    var result = std.ArrayList(APDefinition).init(self.allocator);
    for (aps.items, 0..) |idr, i| {
        const ap = try result.addOne();
        try SWD.select_ap(self, @truncate(i));
        try SWD.mem_setup(self);

        _ = try SWD.read_dap_reg(self, definitions.AP_MEM_BASE_LO);
        const base: definitions.AP_MEM_BASE_LO = try SWD.read_dap_reg_as(self, definitions.RDBUFF, definitions.AP_MEM_BASE_LO);
        ap.component = try probe_coresight_element(self, @as(u32, @intCast(base.BASEADDR_LO)) << 12, 0);
        ap.idr = idr;
    }

    aps.clearAndFree();

    return result;
}
