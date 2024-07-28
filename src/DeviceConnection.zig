const std = @import("std");

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

fn Promise(comptime T: type) type {
    const HeapType = struct {
        value: ?T = null,
        sema: std.Thread.Semaphore = {},
    };
    return struct {
        allocator: std.mem.Allocator,
        heap: ?*HeapType = null,

        fn init(allocator: std.mem.Allocator) !@This() {
            const result = .{
                .allocator = allocator,
                .heap = try allocator.create(HeapType),
            };
            result.heap.value = null;
            result.heap.sema = .{};

            return result;
        }

        fn fulfill(self: @This(), val: T) void {
            if (self.heap == null) return;
            self.heap.?.value = val;
            self.heap.?.sema.post();
        }

        pub fn wait(self: *@This()) ?T {
            if (self.heap == null) return null;
            self.heap.?.sema.wait();
            const result = self.heap.?.value;
            self.allocator.destroy(self.heap.?);
            self.heap = null;
            return result.?;
        }

        pub fn poll(self: *@This()) ?T {
            if (self.heap == null) return null;
            if (self.heap.?.sema.permits > 0) {
                const result = self.heap.?.value;
                self.allocator.destroy(self.heap.?);
                self.heap = null;
                return result;
            } else return null;
        }

        pub fn discard(self: *@This()) void {
            self.allocator.destroy(self.heap.?);
            self.heap = null;
        }
    };
}

const DeviceQueue = struct {
    queue: [QueueSize]QueueItem,
    mutex: std.Thread.Mutex = .{},
    head: u32 = 0,
    tail: u32 = 0,

    const QueueSize = 5;

    const QueueItemHdr = enum(usize) {
        none,
        init,
        read_reg,
        write_reg,
    };
    const QueueItem = struct {
        typ: QueueItemHdr,
        val1: u32,
        val2: u32,
        promise: Promise(u32),
    };

    const QueueError = error{
        QueueFull,
    };

    fn init(allocator: std.mem.Allocator) !@This() {
        var result: @This() = undefined;
        result.head = 0;
        result.tail = 0;
        result.mutex = .{};

        for (&result.queue) |*item| {
            item.val1 = 0;
            item.val2 = 0;
            item.typ = .none;
            item.promise = try Promise(u32).init(allocator);
        }

        return result;
    }

    fn push(self: *@This(), typ: QueueItemHdr, val1: u32, val2: u32) !Promise(u32) {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.tail == ((self.head + 1) % QueueSize)) return QueueError.QueueFull;

        self.queue[self.head].typ = typ;
        self.queue[self.head].val1 = val1;
        self.queue[self.head].val2 = val2;

        const result = self.queue[self.head].promise;
        self.head = ((self.head + 1) % QueueSize);
        return result;
    }

    fn pop(self: *@This()) ?QueueItem {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.head == self.tail) {
            return null;
        }

        const result = self.queue[self.tail];
        self.tail = ((self.tail + 1) % QueueSize);

        return result;
    }
};

const QueueBuffer = struct { std.RingBuffer() };

const usb_buf_size = 0x1000; // 4kb
const ProcessedDeviceList = std.ArrayList(ChoosableDevice);

const c = @cImport({
    @cDefine("MIDL_INTERFACE", "struct");
    @cInclude("libusb.h");
});

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

const SwdWriteOp = struct {
    Start: u1 = 1,
    APnDP: enum(u1) {
        AP = 1,
        DP = 0,
    },
    RnW: enum(u1) {
        R = 1,
        W = 0,
    },
    A: u2,
    Parity: u1,
    Stop: u1 = 0,
    Park: u1 = 1,
    Trn1: u1 = 0,
    Ack: u3 = 0,
    Trn2: u1 = 0,

    const Dir = SwdWriteOp{
        .Start = 1, // Out
        .APnDP = 1, // Out
        .RnW = 1, // Out
        .A = 0x3, // Out
        .Parity = 1, // Out
        .Stop = 1, // Out
        .Park = 1, // Out
        .Trn1 = 0, // Turnaround (In)
        .Ack = 0, // In
        .Trn2 = 0, // Turnaround (In)
    };
};

const SwdReadData = struct {
    data: u32,
    parity: u1,

    const Dir = SwdReadData{
        .data = 0x00000000, // In
        .parity = 0x0, // In
    };
};

const SwdWriteData = struct {
    data: u32,
    parity: u1,

    const Dir = SwdWriteData{
        .data = 0xFFFFFFFF, // Out
        .parity = 0x1, // Out
    };
};

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
