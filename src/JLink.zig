const definitions = @import("definitions.zig");
const std = @import("std");
const c = @import("c.zig");

const DeviceConnection = @import("DeviceConnection.zig");

const JLINK_ENDPOINT_IN = 0x81;
const JLINK_ENDPOINT_OUT = 0x02;

pub const Error = error{
    SwdFault,
    NeedReset,
};

pub const SwdInfo = struct {
    APnDP: definitions.APnDP = .DP,
    RnW: definitions.RnW = .W,
    A: definitions.A32 = .A00,
    DATA: u32 = 0x00000000,
};

fn xfer_usb(self: *DeviceConnection, out: usize, in: usize) !void {
    var actual_len: c_int = 0;
    var in_cnt: c_int = @intCast(in);
    var out_cnt: c_int = @intCast(out);
    while (out_cnt != 0) {
        _ = c.libusb_bulk_transfer(self.current_device, JLINK_ENDPOINT_OUT, self.usb_read_buf.ptr + (out - @as(usize, @intCast(out_cnt))), out_cnt, &actual_len, 1000);
        if (actual_len == 0) {
            return Error.NeedReset;
        }
        out_cnt -= actual_len;
    }
    while (in_cnt != 0) {
        _ = c.libusb_bulk_transfer(self.current_device, JLINK_ENDPOINT_IN, self.usb_read_buf.ptr + (in - @as(usize, @intCast(in_cnt))), in_cnt, &actual_len, 1000);
        if (actual_len == 0) {
            return Error.NeedReset;
        }
        in_cnt -= actual_len;
    }
}

fn reset_device(self: *DeviceConnection) !void {
    self.usb_read_buf[0] = 0x02;

    try xfer_usb(self, 1, 0);
}

fn set_speed(self: *DeviceConnection, speed_in_khz: u16) !void {
    var out_stream = std.io.fixedBufferStream(self.usb_read_buf);
    var writer = out_stream.writer();

    try writer.writeInt(u8, 0x05, .little); // CMD_SELECT_IF
    try writer.writeInt(u16, speed_in_khz, .little); // Choose SWD

    try xfer_usb(self, 3, 0);
}

fn set_if(self: *DeviceConnection) !void {
    var out_stream = std.io.fixedBufferStream(self.usb_read_buf);
    var writer = out_stream.writer();

    try writer.writeInt(u8, 0xC7, .little); // CMD_SELECT_IF
    try writer.writeInt(u8, 0x01, .little); // Choose SWD

    try xfer_usb(self, 2, 4);
}

pub fn init(self: *DeviceConnection) !void {
    try reset_device(self);
    try set_speed(self, 3);
    try set_if(self);
}

pub fn swd_reset(self: *DeviceConnection) !void {
    var out_stream = std.io.fixedBufferStream(self.usb_read_buf);
    const writer = out_stream.writer();

    try writer.writeInt(u16, 0x00CF, .little); // Command ID
    try writer.writeInt(u16, 52, .little); // # of Bits (52)

    // Dir
    try writer.writeByteNTimes(0xFF, 6);
    try writer.writeByte(0x0F);

    // Out
    try writer.writeByteNTimes(0xFF, 6);
    try writer.writeByte(0x03);

    try xfer_usb(self, 18, 8);
}

pub fn swd(self: *DeviceConnection, info: SwdInfo) !u32 {
    // JLink automatically ignores turnarounds when filling the read field,
    // but needs them still on the write field
    self.usb_read_buf[2] = 0b00000010;
    while (self.usb_read_buf[2] == 0b00000010) {
        var out_stream = std.io.fixedBufferStream(self.usb_read_buf);
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

        try xfer_usb(self, 18, 8);

        if (self.usb_read_buf[7] != 0) {
            return Error.NeedReset;
        } else if ((self.usb_read_buf[2] & 7) == 1) { // Continue
        } else if ((self.usb_read_buf[2] & 7) == 2) { // Continue
        } else if ((self.usb_read_buf[2] & 7) == 4) {
            return Error.SwdFault;
        } else return Error.NeedReset;
    }

    // Handle data in
    switch (info.RnW) {
        .R => {
            var in_stream = std.io.fixedBufferStream(self.usb_read_buf);
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
