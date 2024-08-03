const definitions = @import("definitions.zig");
const std = @import("std");
const c = @import("c.zig");

const DeviceConnection = @import("DeviceConnection.zig");

const JLINK_ENDPOINT_IN = 0x81;
const JLINK_ENDPOINT_OUT = 0x02;

const Error = error{
    SwdWait,
    SwdFault,
    SwdOther,
    JLink,
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
            return Error.JLink;
        }
        out_cnt -= actual_len;
    }
    while (in_cnt != 0) {
        _ = c.libusb_bulk_transfer(self.current_device, JLINK_ENDPOINT_IN, self.usb_read_buf.ptr + (in - @as(usize, @intCast(in_cnt))), in_cnt, &actual_len, 1000);
        if (actual_len == 0) {
            return Error.JLink;
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
    try reset(self);

    const tid = try self.read_dap_reg(definitions.DPIDR);
    std.debug.print("Revision:{x}, Partno:{x}, Min:{x} Version:{x} Designer:{x}\n", .{ tid.REVISION, tid.PARTNO, tid.MIN, tid.VERSION, tid.DESIGNER });

    // Clear flags
    _ = try swd(self, .{ .APnDP = .DP, .RnW = .W, .A = .A00, .DATA = 0x0000001E });

    _ = try self.read_dap_reg(definitions.DLCR);

    const tid2 = try self.read_dap_reg(definitions.DPIDR);
    std.debug.print("Revision:{x}, Partno:{x}, Min:{x} Version:{x} Designer:{x}\n", .{ tid2.REVISION, tid2.PARTNO, tid2.MIN, tid2.VERSION, tid2.DESIGNER });
}

pub fn reset(self: *DeviceConnection) !void {
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
    // J-Link is weird
    // For some reason it puts the turnaround bits together
    // whenever switching to write?
    // Idk it just seems to work this way

    var out_stream = std.io.fixedBufferStream(self.usb_read_buf);
    var writer = out_stream.writer();
    try writer.writeInt(u16, 0x00CF, .little); // Command ID
    switch (info.RnW) {
        .R => {
            try writer.writeInt(u16, 11, .little); // # of Bits (cmd+ack)
            // Dir
            try writer.writeByte(0xFF); // CMD
            try writer.writeByte(0x00); // Spaces for ACK
        },
        .W => {
            try writer.writeInt(u16, 13, .little); // # of Bits (cmd+ack+2trn)
            // Dir
            try writer.writeByte(0xFF); // CMD
            try writer.writeByte(0x00); // Spaces for ACK
        },
    }

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

    try writer.writeByte(cmd); // CMD
    try writer.writeByte(0x00); // Spaces for Trn1, ACK

    try xfer_usb(self, 8, 3);

    if (self.usb_read_buf[2] != 0) {
        return Error.JLink;
    }
    if ((self.usb_read_buf[1] & 0b00000100) > 0) {
        return Error.SwdWait;
    }
    if ((self.usb_read_buf[1] & 0b00000010) > 0) {
        return Error.SwdFault;
    }

    // Now handle the data
    out_stream = std.io.fixedBufferStream(self.usb_read_buf);
    writer = out_stream.writer();

    try writer.writeInt(u16, @as(u16, 0x00CF), .little); // Command ID

    // Dir and Out
    switch (info.RnW) {
        .R => {
            try writer.writeInt(u16, @as(u16, 35), .little); // # of Bits (data+parity+2trn)
            // Dir
            try writer.writeInt(u32, 0x00000000, .little);
            try writer.writeByte(0x00); // For parity
            // Out
            try writer.writeInt(u32, 0, .little);
            try writer.writeByte(0x00);
        },
        .W => {
            try writer.writeInt(u16, @as(u16, 33), .little); // # of Bits (data+parity+1trn)
            // Dir
            try writer.writeInt(u32, 0xFFFFFFFF, .little);
            try writer.writeByte(0x01);
            // Out
            try writer.writeInt(u32, info.DATA, .little);
            var lastByte: u8 = 0;
            if ((@popCount(info.DATA) & 1) > 0) {
                lastByte |= 0x1;
            }
            try writer.writeByte(lastByte);
        },
    }

    switch (info.RnW) {
        .R => {
            try xfer_usb(self, 14, 6);

            if (self.usb_read_buf[5] != 0) {
                return Error.JLink;
            }
            var in_stream = std.io.fixedBufferStream(self.usb_read_buf);
            const reader = in_stream.reader();
            const result = try reader.readInt(u32, .little);
            return result;
        },
        .W => {
            try xfer_usb(self, 14, 6);

            if (self.usb_read_buf[5] != 0) {
                return Error.JLink;
            }
            return 0;
        },
    }
}
