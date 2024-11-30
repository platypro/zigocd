pub const name = .usb;

pub const Error = error{
    NoDevice,
};

pub const vtable = struct {
    getDevices: *const fn (
        api: *ocd.API,
        valid_vendors: []const u16,
        valid_products: []const u16,
    ) anyerror![]ChoosableDevice,
    connect: *const fn (
        api: *ocd.API,
        device: ChoosableDevice,
    ) anyerror!ocd.Handle,
    disconnect: *const fn (
        api: *ocd.API,
        handle: ocd.Handle,
    ) anyerror!void,
    bulkXfer: *const fn (
        api: *ocd.API,
        ctx: ocd.Handle,
        addr: usize,
        buf: []u8,
    ) anyerror!usize,
};

const ocd = @import("../root.zig");

pub const ChoosableDevice = struct {
    bus: u16,
    port: u16,
    manufacturer_str: []const u8,
    product_str: []const u8,
    has_driver: bool,
    handle: ocd.Handle,
};

pub fn init(self: *ocd.API) !void {
    _ = self;
}

pub fn deinit(self: *ocd.API) void {
    _ = self;
}
