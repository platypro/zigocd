pub const name = .jlink;

pub fn init(self: *cxmdb.Node) !void {
    self.user_data = .{ .jlink = try self.allocator.create(@This()) };

    const swd_vtable = cxmdb.API.api_vtable_union{ .swd = .{ .swd = swd, .swd_reset = swd_reset } };

    const ctx = try self.getContext(.jlink);
    ctx.connection_handle = null;
    ctx.read_buf = try self.allocator.alloc(u8, 1024);

    try self.register_api(.swd, swd_vtable);
}

pub fn deinit(self: *cxmdb.Node) void {
    const ctx = self.getContext(.jlink) catch return;
    self.allocator.free(ctx.read_buf);
    self.allocator.destroy(self.user_data.?.jlink);
}

connection_handle: ?cxmdb.Handle,
read_buf: []u8,

pub const Error = error{
    NoDevice,
    BadTransport,
    JLinkNotInitialized,
};

const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");

const USB = @import("../API/USB.zig");
const SWD = @import("../API/SWD.zig");

const JLINK_ENDPOINT_IN = 0x81;
const JLINK_ENDPOINT_OUT = 0x02;

const buf_size = 0x1000; // 4kb

fn swd(self: *cxmdb.API, info: SWD.SwdInfo) !u32 {
    const jlink = try self.getParentContext(.jlink);
    // JLink automatically ignores turnarounds when filling the read field,
    // but needs them still on the write field
    jlink.read_buf[2] = 0b00000010;
    while (jlink.read_buf[2] == 0b00000010) {
        var out_stream = std.io.fixedBufferStream(jlink.read_buf);
        var writer = out_stream.writer();
        var bit_writer = std.io.bitWriter(.little, writer);
        try writer.writeInt(u16, 0x00CF, .little); // Command ID
        switch (info.RnW) {
            .R => { // Length
                try writer.writeInt(u16, 54, .little); // # of Bits (cmd+ack+data+parity)
            },
            .W => {
                try writer.writeInt(u16, 54, .little); // # of Bits (cmd+ack+data+parity + 2????)
            },
        }

        // Dir
        try writer.writeByte(0xFF); // Idle
        try writer.writeByte(0xFF); // CMD
        try bit_writer.writeBits(@as(u32, 0x00), 3); // Spaces for ACK
        switch (info.RnW) {
            .R => { // Dir
                try bit_writer.writeBits(@as(u32, 0x00), 32); // Data
                try bit_writer.writeBits(@as(u32, 0x06), 3); // Parity + 2trn
            },
            .W => {
                // Dir
                try bit_writer.writeBits(@as(u32, 0x00), 2); // +2?
                try bit_writer.writeBits(@as(u32, 0xFFFFFFFF), 32); // Data
                try bit_writer.writeBits(@as(u32, 0x07), 3); // Parity
            },
        }

        try bit_writer.flushBits();

        // Out
        var cmd: u8 = 0;
        cmd |= @intFromEnum(info.APnDP);
        cmd |= @intFromEnum(info.RnW);
        cmd |= @intFromEnum(info.A);

        // Parity
        if ((@popCount(cmd) & 1) > 0) {
            cmd |= 0b00100000;
        }

        // Add Start and Park
        cmd |= 0b10000001;

        try writer.writeByte(0x00); // IDLE
        try writer.writeByte(cmd); // CMD
        try bit_writer.writeBits(@as(u32, 0x00), 3); // Spaces for ACK

        switch (info.RnW) {
            .R => {
                // Out
                try bit_writer.writeBits(@as(u32, 0x00), 32); // Data
                try bit_writer.writeBits(@as(u32, 0x00), 3); // Parity
            },
            .W => {
                // Out
                try bit_writer.writeBits(@as(u32, 0), 2);
                try bit_writer.writeBits(@as(u8, @truncate(info.DATA)), 8);
                try bit_writer.writeBits(@as(u8, @truncate(info.DATA >> 8)), 8);
                try bit_writer.writeBits(@as(u8, @truncate(info.DATA >> 16)), 8);
                try bit_writer.writeBits(@as(u8, @truncate(info.DATA >> 24)), 8);
                if ((@popCount(info.DATA) & 1) > 0) {
                    try bit_writer.writeBits(@as(u32, 1), 3);
                } else {
                    try bit_writer.writeBits(@as(u32, 0), 3);
                }
            },
        }

        try bit_writer.flushBits();

        try xfer(self.parent_node, 18, 8);

        if (jlink.read_buf[7] != 0) {
            return SWD.Error.NeedReset;
        } else if ((jlink.read_buf[2] & 7) == 1) { // Continue
        } else if ((jlink.read_buf[2] & 7) == 2) {
            std.debug.print("Wait Error!\n", .{});
            return SWD.Error.Wait;
        } else if ((jlink.read_buf[2] & 7) == 4) {
            return SWD.Error.Fault;
        } else return SWD.Error.NeedReset;
    }

    // Handle data in
    switch (info.RnW) {
        .R => {
            var in_stream = std.io.fixedBufferStream(jlink.read_buf);
            const reader = in_stream.reader();
            var bit_reader = std.io.bitReader(.little, reader);
            var out_bits: usize = 0;
            _ = try bit_reader.readBits(u32, 19, &out_bits);
            const result = try bit_reader.readBits(u32, 32, &out_bits);
            return result;
        },
        .W => {
            return 0;
        },
    }
}

fn swd_reset(self: *cxmdb.API) !void {
    const jlink = try self.getParentContext(.jlink);
    var out_stream = std.io.fixedBufferStream(jlink.read_buf);
    const writer = out_stream.writer();

    try writer.writeInt(u16, 0x00CF, .little); // Command ID
    try writer.writeInt(u16, 52, .little); // # of Bits (52)

    // Dir
    try writer.writeByteNTimes(0xFF, 6);
    try writer.writeByte(0x0F);

    // Out
    try writer.writeByteNTimes(0xFF, 6);
    try writer.writeByte(0x03);

    try xfer(self.parent_node, 18, 8);
}

fn xfer(self: *cxmdb.Node, out: usize, in: usize) !void {
    if (self.transport == null) return;
    const xport = self.transport.?;
    const jlink = try self.getContext(.jlink);

    if (jlink.connection_handle == null) return Error.JLinkNotInitialized;

    var actual_len: usize = 0;
    var in_cnt: usize = in;
    var out_cnt: usize = out;
    while (out_cnt != 0) {
        switch (xport.type) {
            .usb => {
                actual_len = try xport.vtable.usb.bulkXfer(
                    xport,
                    jlink.connection_handle.?,
                    JLINK_ENDPOINT_OUT,
                    jlink.read_buf[out - out_cnt .. out],
                );
            },
            else => {},
        }
        if (actual_len == 0) {
            return SWD.Error.NeedReset;
        }
        out_cnt -= actual_len;
    }
    while (in_cnt != 0) {
        switch (xport.type) {
            .usb => {
                actual_len = try xport.vtable.usb.bulkXfer(
                    xport,
                    jlink.connection_handle.?,
                    JLINK_ENDPOINT_IN,
                    jlink.read_buf[in - in_cnt .. in],
                );
            },
            else => {},
        }
        if (actual_len == 0) {
            return SWD.Error.NeedReset;
        }
        in_cnt -= actual_len;
    }
}

fn set_speed(self: *cxmdb.Node, speed_in_khz: u16) !void {
    const jlink = self.user_data.?.jlink;
    var out_stream = std.io.fixedBufferStream(jlink.read_buf);
    var writer = out_stream.writer();

    try writer.writeInt(u8, 0x05, .little); // CMD_SELECT_IF
    try writer.writeInt(u16, speed_in_khz, .little); // Choose SWD

    try xfer(self, 3, 0);
}

fn set_if(self: *cxmdb.Node) !void {
    const jlink = self.user_data.?.jlink;
    var out_stream = std.io.fixedBufferStream(jlink.read_buf);
    var writer = out_stream.writer();

    try writer.writeInt(u8, 0xC7, .little); // CMD_SELECT_IF
    try writer.writeInt(u8, 0x01, .little); // Choose SWD

    try xfer(self, 2, 4);
}

fn reset_device(self: *cxmdb.Node) !void {
    const jlink = self.user_data.?.jlink;
    jlink.read_buf[0] = 0x02;

    try xfer(self, 1, 0);
}

pub fn connect_to_first(self: *cxmdb.Node) !void {
    if (self.transport == null) return;
    const xport = self.transport.?;
    if (xport.type != .usb) {
        return Error.BadTransport;
    }

    const ctx = try self.getContext(.jlink);
    const vtable = xport.getVtable(.usb);

    const devices: []USB.ChoosableDevice = try vtable.getDevices(xport, &.{0x1366}, &.{});
    if (devices.len == 0) {
        return Error.NoDevice;
    }

    ctx.connection_handle = try vtable.connect(xport, devices[0]);

    try reset_device(self);
    try set_speed(self, 3);
    try set_if(self);
}
