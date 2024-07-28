const std = @import("std");

const DeviceQueue = @import("DeviceQueue.zig");
const Promise = @import("Promise.zig").Promise;
const definitions = @import("definitions.zig");

allocator: std.mem.Allocator,
usb_ctx: ?*c.libusb_context,
cached_devices: [*c]?*c.libusb_device,
cached_processed_devices: ProcessedDeviceList,
current_device: ?*c.libusb_device_handle = null,
evt_thread: std.Thread,
cmd_queue_thread: std.Thread,
cmd_queue: DeviceQueue,
usb_read_buf: []u8,
exit: c_int,

const Error = error{
    LibUsbError,
    DeviceNoLongerAvailable,
};

const usb_buf_size = 0x1000; // 4kb
const ProcessedDeviceList = std.ArrayList(ChoosableDevice);

const c = @cImport({
    @cDefine("MIDL_INTERFACE", "struct");
    @cInclude("libusb.h");
});

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
    handle: usize, // Index into cached_devices array

    const Type = enum {
        jlink,
    };
};

const JLINK_ENDPOINT_IN = 0x81;
const JLINK_ENDPOINT_OUT = 0x02;

fn evt_cb(ctx: *@This()) void {
    while (ctx.exit == 0) {
        if (c.libusb_handle_events_completed(ctx.usb_ctx, &ctx.exit) != c.LIBUSB_SUCCESS) {
            return;
        }
    }
}

fn cmd_queue_cb(ctx: *@This()) void {
    while (ctx.exit == 0) {
        const instr_opt = ctx.cmd_queue.pop();
        if (instr_opt != null) {
            const instr = instr_opt.?;
            switch (instr.typ) {
                .none => return,
                .init => {
                    instr.promise.fulfill(0);
                },
                .read_reg => {},
                .write_reg => {},
            }
        }
    }
}

pub fn init(allocator: std.mem.Allocator) !*@This() {
    var self: *@This() = try allocator.create(@This());
    if (c.libusb_init(@ptrCast(&self.usb_ctx)) != 0) {
        return Error.LibUsbError;
    }

    self.exit = 0;
    self.allocator = allocator;
    self.cached_processed_devices = ProcessedDeviceList.init(allocator);
    self.cached_devices = null;
    self.current_device = null;
    self.cmd_queue = try DeviceQueue.init(allocator);
    self.usb_read_buf = try allocator.alloc(u8, usb_buf_size);
    self.evt_thread = try std.Thread.spawn(.{ .allocator = allocator, .stack_size = 1024 }, evt_cb, .{self});
    self.cmd_queue_thread = try std.Thread.spawn(.{ .allocator = allocator, .stack_size = 1024 }, cmd_queue_cb, .{self});

    return self;
}

pub fn deinit(self: *@This()) void {
    self.exit = 1;
    if (self.current_device != null) {
        c.libusb_close(self.current_device);
        self.current_device = null;
        self.cmd_queue_thread.join();
        self.evt_thread.join();
    }

    self.allocator.free(self.usb_read_buf);
    for (self.cached_processed_devices.items) |dev| {
        self.allocator.free(dev.manufacturer_str);
        self.allocator.free(dev.product_str);
    }
    self.cached_processed_devices.deinit();

    c.libusb_exit(self.usb_ctx);
    self.usb_ctx = null;

    self.allocator.destroy(self);
}

fn jlink_write_op(self: *@This(), comptime T: type, in: T, dir: T) Promise(T) {
    const a: c.struct_libusb_transfer = undefined;

    // Fill buffer
    var instream = std.io.fixedBufferStream(self.usb_read_buf);
    var writer = instream.writer();
    var seeker = instream.seekableStream();
    writer.writeInt(u16, 0x00CD, .little);
    seeker.seekBy(2);
    const bit_writer = std.io.bitWriter(.little, instream);

    // Write direction and count bits
    var num_bits = 0;
    inline for (@typeInfo(T).Struct.fields) |field| {
        bit_writer.writeBits(@field(dir, field.name), @TypeOf(field).Int.bits);
        num_bits = num_bits + @TypeOf(field).Int.bits;
    }
    bit_writer.flushBits();

    // Write input
    inline for (@typeInfo(T).Struct.fields) |field| {
        bit_writer.writeBits(@field(in, field.name), @TypeOf(field).Int.bits);
    }
    bit_writer.flushBits();

    const buf_size = instream.getPos();

    // Write size
    seeker.seekTo(2);
    writer.writeInt(u16, num_bits, .little);

    const cb = struct {
        fn cb(xfer: [*c]c.struct_libusb_transfer) callconv(.C) void {
            var out: T = undefined;
            const outstream = std.io.fixedBufferStream(xfer.*.buffer);
            var bit_reader = std.io.bitReader(.little, outstream);
            inline for (@typeInfo(T).Struct.fields) |field| {
                bit_writer.writeBits(@field(in, field.name), @TypeOf(field).Int.bits);
                var out_bits: usize = 0;
                @field(out, field.name) = try bit_reader.readBits(field.type, @TypeOf(field).Int.bits, &out_bits);
            }
        }
    }.cb;

    const result = Promise(T).init(self.alloc);

    c.libusb_fill_bulk_transfer(&a, self.current_device, JLINK_ENDPOINT_OUT, self.usb_read_buf, buf_size, cb, result.heap, 0);

    return result;
}

pub fn read_reg(self: *@This(), addr: u32) Promise(u32) {
    self.cmd_queue.push(.read_reg, addr);
}

pub fn get_devices(self: *@This()) ![]ChoosableDevice {
    const dev_count: usize = @intCast(c.libusb_get_device_list(self.usb_ctx, @ptrCast(&self.cached_devices)));

    for (0..dev_count, self.cached_devices[0..dev_count]) |i, device| {
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

pub fn choose_device(self: *@This(), dev: ChoosableDevice) !Promise(u32) {
    if (self.current_device != null) {
        c.libusb_close(self.current_device);
        self.current_device = null;
    }

    if (c.libusb_open(self.cached_devices[dev.handle], &self.current_device) != 0) {
        return Error.DeviceNoLongerAvailable;
    }

    return try self.cmd_queue.push(.init, 0, 0);
}
