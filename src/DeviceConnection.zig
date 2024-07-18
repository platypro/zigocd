const std = @import("std");

const Error = error{
    LibUsbError,
};

allocator: std.mem.Allocator,
usb_ctx: ?*c.libusb_context,
cached_devices: [*c]?*c.libusb_device,
cached_processed_devices: ProcessedDeviceList,
usb_read_buf: []u8,

const usb_buf_size = 0x1000; // 4kb
const ProcessedDeviceList = std.ArrayList(ChoosableDevice);

const c = @cImport({
    @cDefine("MIDL_INTERFACE", "struct");
    @cInclude("libusb.h");
});

pub fn init(allocator: std.mem.Allocator) !@This() {
    var self: @This() = undefined;
    if (c.libusb_init(@ptrCast(&self.usb_ctx)) != 0) {
        return Error.LibUsbError;
    }

    self.allocator = allocator;
    self.cached_processed_devices = ProcessedDeviceList.init(allocator);
    self.cached_devices = null;
    self.usb_read_buf = try allocator.alloc(u8, usb_buf_size);

    return self;
}

pub fn deinit(self: @This()) void {
    self.allocator.free(self.usb_read_buf);
    for (self.cached_processed_devices.items) |dev| {
        self.allocator.free(dev.manufacturer_str);
        self.allocator.free(dev.product_str);
    }
    self.cached_processed_devices.deinit();
}

const state = enum {
    unconnected_from_probe,
    unconnected_from_device,
    connected_to_device,
};

const ChoosableDevice = struct {
    typ: Type,
    bus: u16,
    port: u16,
    manufacturer_str: []const u8,
    product_str: []const u8,
    has_driver: bool,

    const Type = enum {
        jlink,
    };
};

pub fn get_devices(self: *@This()) ![]ChoosableDevice {
    const dev_count: usize = @intCast(c.libusb_get_device_list(self.usb_ctx, @ptrCast(&self.cached_devices)));

    for (self.cached_devices[0..dev_count]) |device| {
        var descriptor: c.struct_libusb_device_descriptor = undefined;
        var cached_device: ChoosableDevice = undefined;
        if (c.libusb_get_device_descriptor(device, @ptrCast(&descriptor)) != 0) {
            continue;
        }

        switch (descriptor.idVendor) {
            0x1366 => cached_device.typ = .jlink,
            else => continue,
        }

        var device_handle: ?*c.libusb_device_handle = undefined;
        cached_device.bus = c.libusb_get_bus_number(device);
        cached_device.port = c.libusb_get_port_number(device);
        cached_device.manufacturer_str = &.{};
        cached_device.product_str = &.{};
        switch (c.libusb_open(device, &device_handle)) {
            0 => {
                cached_device.has_driver = true;
            },
            c.LIBUSB_ERROR_NOT_SUPPORTED => {
                cached_device.has_driver = false;
                try self.cached_processed_devices.append(cached_device);
                continue;
            },
            else => {
                continue;
            },
        }
        defer c.libusb_close(device_handle);

        _ = c.libusb_get_string_descriptor(
            device_handle,
            0,
            0,
            self.usb_read_buf.ptr,
            @intCast(self.usb_read_buf.len),
        );
        const langcode = std.mem.readPackedInt(u16, self.usb_read_buf[2..4], 0, .little);
        _ = c.libusb_get_string_descriptor(
            device_handle,
            descriptor.iManufacturer,
            langcode,
            self.usb_read_buf.ptr,
            258,
        );
        _ = c.libusb_get_string_descriptor(
            device_handle,
            descriptor.iProduct,
            langcode,
            self.usb_read_buf.ptr + 258,
            258,
        );

        const len1: u16 = @divExact(self.usb_read_buf[0], 2);
        const len2: u16 = @divExact(@as(u16, @intCast(self.usb_read_buf[258])) + 258, 2);

        const reinterpreted_read_buf = @as([*]u16, @alignCast(@ptrCast(self.usb_read_buf.ptr)))[0..@divExact(516, 2)];

        cached_device.manufacturer_str = try std.unicode.utf16LeToUtf8Alloc(self.allocator, reinterpreted_read_buf[1..len1]);
        cached_device.product_str = try std.unicode.utf16LeToUtf8Alloc(self.allocator, reinterpreted_read_buf[130..len2]);

        try self.cached_processed_devices.append(cached_device);
    }

    return self.cached_processed_devices.items;
}

pub fn choose_device(self: @This(), dev: ChoosableDevice) Device {
    _ = self;
    _ = dev;
}

const Device = struct { handle: c.libusb_device };
