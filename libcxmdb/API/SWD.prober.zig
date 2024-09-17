const definitions = @import("SWD.definitions.zig");

const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");
const SWD = @import("SWD.zig");
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
        OTHER: void,
    },
};

const APDefinition = struct {
    idr: definitions.AP_IDR,
    component: Component,
};

pub fn read_coresight_register(self: *cxmdb.API, base: u32, Reg: type) !Reg {
    const val = try SWD.read_mem_single(self, base + Reg.addr);
    return SWD.u32ToStruct(Reg, val);
}

pub fn write_coresight_register(self: *cxmdb.API, base: u32, reg: anytype) void {
    const val: u32 = SWD.structToU32(reg);
    _ = SWD.write_mem(self, base + reg.addr, &val);
}

fn probe_coresight_element(self: *cxmdb.API, base: u32, depth: u32) !Component {
    if (depth > 2) {
        return Error.Recursion;
    }

    const cidr1 = try read_coresight_register(self, base, definitions.CORESIGHT_CIDR1);
    var result: Component = undefined;
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

                var processed_entry = try result.data.ROMTABLE.entries.addOne();
                processed_entry.entry = try SWD.u32ToStruct(definitions.ROMTABLE_ROMENTRY, entry);

                if (processed_entry.entry.PRESENT == 0) continue;

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
        .OTHER => {
            result.data = .{ .OTHER = {} };
        },
    }

    return result;
}

pub fn probe(self: *cxmdb.API) !std.ArrayList(APDefinition) {
    try SWD.setup_connection(self);
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
