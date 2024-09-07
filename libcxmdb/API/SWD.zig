const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");
pub const definitions = @import("SWD.definitions.zig");

pub const name = .swd;
pub const vtable = struct {
    swd_reset: *const fn (self: *cxmdb.API) anyerror!void,
    swd: *const fn (self: *cxmdb.API, info: SwdInfo) anyerror!u32,
};

pub const Error = error{
    Fault,
    NeedReset,
    NoSpaceLeft,
};

// Cached values for SELECT register
cached_select: definitions.SELECT = undefined,
cached_select_old: definitions.SELECT = undefined,

pub const SwdInfo = struct {
    APnDP: definitions.APnDP = .DP,
    RnW: definitions.RnW = .W,
    A: definitions.A32 = .A00,
    DATA: u32 = 0x00000000,
};

pub fn init(self: *cxmdb.API) !void {
    self.user_data = .{ .swd = try self.allocator.create(@This()) };
    self.user_data.?.swd.cached_select = .{ .APBANKSEL = 0, .APSEL = 0, .DPBANKSEL = 0, .RESERVED0 = 0 };
    self.user_data.?.swd.cached_select_old = .{ .APBANKSEL = 0, .APSEL = 0, .DPBANKSEL = 0, .RESERVED0 = 1 };
}

pub fn deinit(self: *cxmdb.API) void {
    self.allocator.destroy(self.user_data.?.swd);
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

pub fn swd(self: *cxmdb.API, info: SwdInfo) anyerror!u32 {
    return self.vtable.swd.swd(self, info);
}

pub fn swd_reset(self: *cxmdb.API) anyerror!void {
    return self.vtable.swd.swd_reset(self);
}

pub fn select_ap(self: *cxmdb.API, id: u8) !void {
    (try self.getContext(.swd)).cached_select.APSEL = id;
}

pub fn query_aps(self: *cxmdb.API) !std.ArrayList(definitions.AP_IDR) {
    var result = std.ArrayList(definitions.AP_IDR).init(self.allocator);
    for (0..255) |i| {
        try select_ap(self, @intCast(i));
        const idr = read_dap_reg(self, definitions.AP_IDR) catch {
            // Clear error flags
            _ = try self.vtable.swd.swd(self, .{ .APnDP = .DP, .RnW = .W, .A = .A00, .DATA = 0x0000001E });
            break;
        };

        if (try structToU32(idr) == 0) {
            break;
        }
        try result.append(idr);
    }
    return result;
}

pub fn update_select_reg(self: *cxmdb.API, Reg: type) !definitions.RegisterAddress {
    if (!@hasDecl(Reg, "addr")) {
        return Error.NoAddr;
    }
    const addr: definitions.RegisterAddress = @field(Reg, "addr");
    const ctx = try self.getContext(.swd);
    if (addr.BANKSEL != null) {
        switch (addr.APnDP) {
            .AP => {
                ctx.cached_select.APBANKSEL = addr.BANKSEL.?;
            },
            .DP => {
                ctx.cached_select.DPBANKSEL = addr.BANKSEL.?;
            },
        }
    }
    if (addr.BANKSEL != null and !std.meta.eql(ctx.cached_select, ctx.cached_select_old)) {
        _ = try self.vtable.swd.swd(self, .{ .APnDP = .DP, .RnW = .W, .A = definitions.SELECT.addr.A, .DATA = try structToU32(ctx.cached_select) });
        ctx.cached_select_old = ctx.cached_select;
    }
    return addr;
}

pub fn read_dap_reg(self: *cxmdb.API, Reg: type) !Reg {
    const addr = try update_select_reg(self, Reg);
    var val: u32 = undefined;
    switch (addr.APnDP) {
        .AP => {
            _ = try self.vtable.swd.swd(self, .{ .APnDP = addr.APnDP, .RnW = .R, .A = addr.A, .DATA = 0 });
            val = try self.vtable.swd.swd(self, .{ .APnDP = definitions.RDBUFF.addr.APnDP, .RnW = .R, .A = definitions.RDBUFF.addr.A, .DATA = 0 });
        },
        .DP => {
            val = try self.vtable.swd.swd(self, .{ .APnDP = addr.APnDP, .RnW = .R, .A = addr.A, .DATA = 0 });
        },
    }
    return u32ToStruct(Reg, val);
}

pub fn write_dap_reg(self: *cxmdb.API, Reg: type, value: Reg) !void {
    const addr = try update_select_reg(self, Reg);
    _ = try self.vtable.swd.swd(self, .{ .APnDP = addr.APnDP, .RnW = .W, .A = addr.A, .DATA = try structToU32(value) });
}

pub fn setup_connection(self: *cxmdb.API) !void {
    try self.vtable.swd.swd_reset(self);

    // Read and report DPIDR register to leave reset
    _ = try read_dap_reg(self, definitions.DPIDR);

    // Clear error flags
    _ = try self.vtable.swd.swd(self, .{ .APnDP = .DP, .RnW = .W, .A = .A00, .DATA = 0x0000001E });

    // Power up system and DP
    var ctrl_stat = try read_dap_reg(self, definitions.CTRL_STAT);
    ctrl_stat.CDBGPWRUPREQ = 1;
    ctrl_stat.CSYSPWRUPREQ = 1;
    ctrl_stat.ORUNDETECT = 1;
    try write_dap_reg(self, definitions.CTRL_STAT, ctrl_stat);

    while (ctrl_stat.CDBGPWRUPACK != 1) {
        ctrl_stat = try read_dap_reg(self, definitions.CTRL_STAT);
    }
}
