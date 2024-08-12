pub const name = .host;

pub fn init(self: *cxmdb.Node) !void {
    self.user_data = .{ .host = try self.allocator.create(@This()) };
    const ctx = try self.getContext(.host);
    ctx.cached_processed_devices = ProcessedDeviceList.init(self.allocator);
    ctx.cached_devices = null;
    ctx.opened_devices = .{};
    ctx.opened_device_count = 0;

    if (c.libusb_init(@ptrCast(&ctx.usb_ctx)) != 0) {
        return Error.LibUsbError;
    }

    const usb_vtable = cxmdb.API.api_vtable_union{ .usb = .{
        .getDevices = usb_getDevices,
        .connect = usb_connect,
        .disconnect = usb_disconnect,
        .bulkXfer = usb_bulkXfer,
    } };

    try self.register_api(.usb, usb_vtable);
}

pub fn deinit(self: *cxmdb.Node) void {
    const ctx = self.getContext(.host) catch return;

    for (ctx.cached_processed_devices.items) |dev| {
        self.allocator.free(dev.manufacturer_str);
        self.allocator.free(dev.product_str);
    }
    ctx.cached_processed_devices.deinit();

    for (ctx.opened_devices.values()) |device| {
        c.libusb_close(device);
    }

    ctx.opened_devices.deinit(self.allocator);
    c.libusb_exit(ctx.usb_ctx);

    self.allocator.destroy(ctx);
}

const Error = error{
    LibUsbError,
    DeviceNoLongerAvailable,
};

const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");
const USB = @import("../API/USB.zig");

const c = @cImport({
    @cDefine("MIDL_INTERFACE", "struct");
    @cInclude("libusb.h");
});

usb_ctx: ?*c.libusb_context,
cached_devices: [*c]?*c.libusb_device,
opened_devices: std.AutoArrayHashMapUnmanaged(cxmdb.Handle, ?*c.libusb_device_handle),
opened_device_count: cxmdb.Handle,
cached_processed_devices: ProcessedDeviceList,

const ProcessedDeviceList = std.ArrayList(USB.ChoosableDevice);

fn usb_getDevices(
    api: *cxmdb.API,
    valid_vendors: []const u16,
    valid_products: []const u16,
) ![]USB.ChoosableDevice {
    const self = try api.getParentContext(.host);
    const dev_count: usize = @intCast(c.libusb_get_device_list(self.usb_ctx, @ptrCast(&self.cached_devices)));

    const buf = try api.allocator.alloc(u8, 1024);
    defer api.allocator.free(buf);

    loop: for (0..dev_count, self.cached_devices[0..dev_count]) |i, device| {
        var descriptor: c.struct_libusb_device_descriptor = undefined;
        var cached_device: USB.ChoosableDevice = undefined;
        if (c.libusb_get_device_descriptor(device, @ptrCast(&descriptor)) != 0) {
            continue;
        }

        choose: {
            for (valid_vendors) |vendor| {
                if (descriptor.idVendor == vendor) {
                    break :choose;
                }
            }

            for (valid_products) |product| {
                if (descriptor.idProduct == product) {
                    break :choose;
                }
            }

            continue :loop;
        }

        var device_handle: ?*c.libusb_device_handle = undefined;
        cached_device.bus = c.libusb_get_bus_number(device);
        cached_device.port = c.libusb_get_port_number(device);
        cached_device.manufacturer_str = &.{};
        cached_device.product_str = &.{};
        cached_device.handle = i;
        switch (c.libusb_open(device, &device_handle)) {
            0 => {
                cached_device.has_driver = true;
                // Fall out of switch
            },
            c.LIBUSB_ERROR_NOT_SUPPORTED => {
                cached_device.has_driver = false;
                try self.cached_processed_devices.append(cached_device);
                continue;
                // Continue device loop
            },
            else => {
                continue;
                // Continue device loop
            },
        }
        defer c.libusb_close(device_handle);

        _ = c.libusb_get_string_descriptor(
            device_handle,
            0,
            0,
            buf.ptr,
            @intCast(buf.len),
        );
        const langcode = std.mem.readPackedInt(u16, buf[2..4], 0, .little);
        _ = c.libusb_get_string_descriptor(
            device_handle,
            descriptor.iManufacturer,
            langcode,
            buf.ptr,
            258,
        );
        _ = c.libusb_get_string_descriptor(
            device_handle,
            descriptor.iProduct,
            langcode,
            buf.ptr + 258,
            258,
        );

        const len1: u16 = @divExact(buf[0], 2);
        const len2: u16 = @divExact(@as(u16, @intCast(buf[258])) + 258, 2);

        const reinterpreted_read_buf = @as([*]u16, @alignCast(@ptrCast(buf.ptr)))[0..@divExact(516, 2)];

        cached_device.manufacturer_str = try std.unicode.utf16LeToUtf8Alloc(api.allocator, reinterpreted_read_buf[1..len1]);
        cached_device.product_str = try std.unicode.utf16LeToUtf8Alloc(api.allocator, reinterpreted_read_buf[130..len2]);
        try self.cached_processed_devices.append(cached_device);
    }

    return self.cached_processed_devices.items;
}

fn usb_connect(
    api: *cxmdb.API,
    device: USB.ChoosableDevice,
) !cxmdb.Handle {
    const self = try api.getParentContext(.host);

    var dev_ptr: ?*c.libusb_device_handle = undefined;

    if (c.libusb_open(self.cached_devices[device.handle], &dev_ptr) != 0) {
        return Error.DeviceNoLongerAvailable;
    }

    try self.opened_devices.put(api.allocator, self.opened_device_count, dev_ptr);
    self.opened_device_count = self.opened_device_count + 1;

    return self.opened_device_count - 1;
}

fn usb_disconnect(api: *cxmdb.API, handle: cxmdb.Handle) !void {
    const self = try api.getParentContext(.host);
    const device = self.opened_devices.get(handle);
    if (device == null) return;
    c.libusb_close(device.?);
    _ = self.opened_devices.swapRemove(handle);
}

fn usb_bulkXfer(
    api: *cxmdb.API,
    ctx: cxmdb.Handle,
    addr: usize,
    buf: []u8,
) !usize {
    const self = try api.getParentContext(.host);
    const device = self.opened_devices.get(ctx);
    if (device == null) {
        return 0;
    }
    var actual_len: usize = 0;
    _ = c.libusb_bulk_transfer(device.?, @intCast(addr), @ptrCast(buf.ptr), @intCast(buf.len), @ptrCast(&actual_len), 1000);
    return actual_len;
}
