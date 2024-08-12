pub const name = .usb;

pub const Error = error{
    NoDevice,
};

pub const vtable = struct {
    getDevices: *const fn (
        api: *cxmdb.API,
        valid_vendors: []const u16,
        valid_products: []const u16,
    ) anyerror![]ChoosableDevice,
    connect: *const fn (
        api: *cxmdb.API,
        device: ChoosableDevice,
    ) anyerror!cxmdb.Handle,
    disconnect: *const fn (
        api: *cxmdb.API,
        handle: cxmdb.Handle,
    ) anyerror!void,
    bulkXfer: *const fn (
        api: *cxmdb.API,
        ctx: cxmdb.Handle,
        addr: usize,
        buf: []u8,
    ) anyerror!usize,
};

const cxmdb = @import("../libcxmdb.zig");

pub const ChoosableDevice = struct {
    bus: u16,
    port: u16,
    manufacturer_str: []const u8,
    product_str: []const u8,
    has_driver: bool,
    handle: cxmdb.Handle,
};

pub fn init(self: *cxmdb.API) !void {
    _ = self;
}

pub fn deinit(self: *cxmdb.API) void {
    _ = self;
}
