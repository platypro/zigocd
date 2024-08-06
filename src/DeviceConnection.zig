const std = @import("std");
const c = @import("c.zig");
const JLink = @import("JLink.zig");

const DeviceQueue = @import("DeviceQueue.zig");
const Promise = @import("Promise.zig").Promise;
const definitions = @import("definitions.zig");

jlink: JLink,
allocator: std.mem.Allocator,
usb_ctx: ?*c.libusb_context,
cached_devices: [*c]?*c.libusb_device,
cached_processed_devices: ProcessedDeviceList,
cmd_queue_thread: std.Thread,
cmd_queue: DeviceQueue,
exit: c_int,
current_device: ?*c.libusb_device_handle,
usb_read_buf: []u8,
// Cached values for SELECT register
cached_select: definitions.SELECT,
cached_select_old: definitions.SELECT,

const usb_buf_size = 0x1000; // 4kb

const Error = error{
    LibUsbError,
    DeviceNoLongerAvailable,
    InvalidRegister,
    NoAddr,
    PacketError,
};

const SwdError = error{
    WDATA,
    STICKYERR,
    STICKYCMP,
    STICKYORUN,
};

const ProcessedDeviceList = std.ArrayList(ChoosableDevice);

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

fn cmd_queue_cb(self: *@This()) !void {
    while (self.exit == 0) {
        const instr_opt = self.cmd_queue.pop();
        if (instr_opt != null) {
            const instr = instr_opt.?;
            switch (instr.typ) {
                .none => return,
                .init => {
                    try JLink.init(self);
                    try JLink.swd_reset(self);

                    // Read and report DPIDR register to leave reset
                    const tid = try self.read_dap_reg(definitions.DPIDR);
                    std.debug.print("Revision:{x}, Partno:{x}, Min:{x} Version:{x} Designer:{x}\n", .{ tid.REVISION, tid.PARTNO, tid.MIN, tid.VERSION, tid.DESIGNER });

                    // Clear error flags
                    _ = try JLink.swd(self, .{ .APnDP = .DP, .RnW = .W, .A = .A00, .DATA = 0x0000001E });

                    // Power up system and DP
                    var ctrl_stat = try self.read_dap_reg(definitions.CTRL_STAT);
                    ctrl_stat.CDBGPWRUPREQ = 1;
                    ctrl_stat.CSYSPWRUPREQ = 1;
                    ctrl_stat.ORUNDETECT = 1;
                    try self.write_dap_reg(definitions.CTRL_STAT, ctrl_stat);
                    //try self.write_dap_reg(definitions.CTRL_STAT, ctrl_stat);

                    //while (ctrl_stat.CSYSPWRUPACK == 0 and ctrl_stat.CDBGPWRUPACK == 0) {

                    while (ctrl_stat.CDBGPWRUPACK != 1) {
                        ctrl_stat = try self.read_dap_reg(definitions.CTRL_STAT);
                        //std.debug.print("SysAck:{x} DbgAck:{x}\n", .{ ctrl_stat.CSYSPWRUPACK, ctrl_stat.CDBGPWRUPACK });
                    }
                    //}

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
    self.cmd_queue_thread = try std.Thread.spawn(.{ .allocator = allocator, .stack_size = 1024 }, cmd_queue_cb, .{self});
    self.cached_select = .{ .APBANKSEL = 0, .APSEL = 0, .DPBANKSEL = 0, .RESERVED0 = 0 };
    self.cached_select_old = .{ .APBANKSEL = 0, .APSEL = 0, .DPBANKSEL = 0, .RESERVED0 = 1 };
    self.usb_read_buf = try allocator.alloc(u8, usb_buf_size);

    return self;
}

pub fn deinit(self: *@This()) void {
    self.exit = 1;
    if (self.current_device != null) {
        c.libusb_close(self.current_device);
        self.current_device = null;
        self.cmd_queue_thread.join();
    }

    for (self.cached_processed_devices.items) |dev| {
        self.allocator.free(dev.manufacturer_str);
        self.allocator.free(dev.product_str);
    }
    self.cached_processed_devices.deinit();

    c.libusb_exit(self.usb_ctx);
    self.usb_ctx = null;

    self.allocator.free(self.usb_read_buf);
    self.allocator.destroy(self);
}

fn u32ToStruct(T: type, val_: u32) !T {
    var val: [4]u8 = @bitCast(val_);
    var bufstream = std.io.fixedBufferStream(&val);
    const reader = bufstream.reader();
    var bit_reader = std.io.bitReader(.little, reader);
    var result: T = undefined;
    inline for (@typeInfo(T).Struct.fields) |field| {
        var out_bits: usize = 0;
        @field(result, field.name) = try bit_reader.readBits(field.type, @typeInfo(field.type).Int.bits, &out_bits);
    }
    return result;
}

fn structToU32(str: anytype) !u32 {
    var result: [4]u8 = undefined;
    var bufstream = std.io.fixedBufferStream(&result);
    const writer = bufstream.writer();
    var bit_writer = std.io.bitWriter(.little, writer);
    inline for (@typeInfo(@TypeOf(str)).Struct.fields) |field| {
        try bit_writer.writeBits(@field(str, field.name), @typeInfo(field.type).Int.bits);
    }
    return @bitCast(result);
}

pub fn update_select_reg(self: *@This(), Reg: type) !definitions.RegisterAddress {
    if (!@hasDecl(Reg, "addr")) {
        return Error.NoAddr;
    }
    const addr: definitions.RegisterAddress = @field(Reg, "addr");
    if (addr.BANKSEL != null) {
        switch (addr.APnDP) {
            .AP => {
                self.cached_select.APBANKSEL = addr.BANKSEL.?;
            },
            .DP => {
                self.cached_select.DPBANKSEL = addr.BANKSEL.?;
            },
        }
    }
    if (addr.BANKSEL != null and !std.meta.eql(self.cached_select, self.cached_select_old)) {
        _ = try JLink.swd(self, .{ .APnDP = .DP, .RnW = .W, .A = definitions.SELECT.addr.A, .DATA = try structToU32(self.cached_select) });
        self.cached_select_old = self.cached_select;
    }
    return addr;
}

const AP = struct {
    typ: enum {
        mem,
        other,
    },
    id: u8,
};

pub fn select_ap(self: *@This(), id: u8) void {
    self.cached_select.APSEL = id;
}

pub fn query_aps(self: *@This()) ![]AP {
    for (0..255) |i| {
        self.select_ap(@intCast(i));
        const idr = self.read_dap_reg(definitions.AP_IDR) catch {
            // Clear error flags
            _ = try JLink.swd(self, .{ .APnDP = .DP, .RnW = .W, .A = .A00, .DATA = 0x0000001E });

            break;
        };

        if (try structToU32(idr) == 0) {
            break;
        }
        std.debug.print("Class:{x} Designer:{x} Revision:{x} TYPE:{x} Variant:{x}\n", .{ idr.CLASS, idr.DESIGNER, idr.REVISION, idr.TYPE, idr.VARIANT });
    }
    return &.{};
}

pub fn read_dap_reg(self: *@This(), Reg: type) !Reg {
    const addr = try self.update_select_reg(Reg);
    var val: u32 = undefined;
    switch (addr.APnDP) {
        .AP => {
            _ = try JLink.swd(self, .{ .APnDP = addr.APnDP, .RnW = .R, .A = addr.A, .DATA = 0 });
            val = try JLink.swd(self, .{ .APnDP = definitions.RDBUFF.addr.APnDP, .RnW = .R, .A = definitions.RDBUFF.addr.A, .DATA = 0 });
        },
        .DP => {
            val = try JLink.swd(self, .{ .APnDP = addr.APnDP, .RnW = .R, .A = addr.A, .DATA = 0 });
        },
    }
    return u32ToStruct(Reg, val);
}

pub fn write_dap_reg(self: *@This(), Reg: type, value: Reg) !void {
    const addr = try self.update_select_reg(Reg);
    _ = try JLink.swd(self, .{ .APnDP = addr.APnDP, .RnW = .W, .A = addr.A, .DATA = try structToU32(value) });
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
