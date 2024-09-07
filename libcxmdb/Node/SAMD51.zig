pub const name = .samd51;

pub fn init(node: *cxmdb.Node) !void {
    _ = node;
}

pub fn deinit(node: *cxmdb.Node) void {
    _ = node;
}

const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");
const SWD = @import("../API/SWD.zig");

pub fn connect(self: *cxmdb.Node) !void {
    switch (self.getTransportVTable()) {
        .swd => {
            try SWD.setup_connection(self.transport.?);
        },
        else => return,
    }
}

pub fn read_reg(self: *cxmdb.Node) !void {
    switch (self.getTransportVTable()) {
        .swd => {
            SWD.select_ap(0);
            SWD.read_dap_reg(self.transport.?, SWD.definitions.AP_MEM_DRW);
        },
    }
}

pub fn write_reg(self: *cxmdb.Node) !void {
    _ = self;
}
