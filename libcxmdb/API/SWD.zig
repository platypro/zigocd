const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");
pub const definitions = @import("SWD.definitions.zig");

pub usingnamespace @import("SWD.prober.zig");

pub const name = .swd;
pub const vtable = struct {
    swd_reset: *const fn (self: *cxmdb.API) anyerror!void,
    swd: *const fn (self: *cxmdb.API, info: SwdInfo) anyerror!u32,
};

pub const Error = error{
    Fault,
    Wait,
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

pub fn u32ToStruct(T: type, val_: u32) !T {
    var val: [4]u8 = @bitCast(val_);
    var bufstream = std.io.fixedBufferStream(&val);
    const reader = bufstream.reader();
    var bit_reader = std.io.bitReader(.little, reader);
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        var out_bits: usize = 0;
        const typ = @typeInfo(field.type);
        switch (typ) {
            .int => {
                @field(result, field.name) = try bit_reader.readBits(field.type, typ.int.bits, &out_bits);
            },
            .@"enum" => {
                @field(result, field.name) = @enumFromInt(try bit_reader.readBits(typ.@"enum".tag_type, @typeInfo(typ.@"enum".tag_type).int.bits, &out_bits));
            },
            else => {},
        }
    }
    return result;
}

pub fn structToU32(str: anytype) !u32 {
    var result: [4]u8 = undefined;
    var bufstream = std.io.fixedBufferStream(&result);
    const writer = bufstream.writer();
    var bit_writer = std.io.bitWriter(.little, writer);
    inline for (@typeInfo(@TypeOf(str)).@"struct".fields) |field| {
        const typ = @typeInfo(field.type);
        switch (typ) {
            .int => {
                try bit_writer.writeBits(@field(str, field.name), typ.int.bits);
            },
            .@"enum" => {
                const enum_val: field.type = @field(str, field.name);
                const int_val = @intFromEnum(enum_val);
                try bit_writer.writeBits(int_val, @typeInfo(typ.@"enum".tag_type).int.bits);
            },
            else => {},
        }
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
        _ = try read_dap_reg(self, definitions.AP_IDR);
        const idr = read_dap_reg_as(self, definitions.RDBUFF, definitions.AP_IDR) catch {
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

pub fn read_dap_reg_raw(self: *cxmdb.API, Reg: type) !u32 {
    const addr = try update_select_reg(self, Reg);
    return try self.vtable.swd.swd(self, .{ .APnDP = addr.APnDP, .RnW = .R, .A = addr.A, .DATA = 0 });
}

pub fn read_dap_reg(self: *cxmdb.API, Reg: type) !Reg {
    return read_dap_reg_as(self, Reg, Reg);
}

pub fn read_dap_reg_as(self: *cxmdb.API, Reg: type, As: type) !As {
    return u32ToStruct(As, try read_dap_reg_raw(self, Reg));
}

pub fn write_dap_reg(self: *cxmdb.API, Reg: type, value: Reg) !void {
    const addr = try update_select_reg(self, Reg);
    _ = try self.vtable.swd.swd(self, .{ .APnDP = addr.APnDP, .RnW = .W, .A = addr.A, .DATA = try structToU32(value) });
}

pub fn mem_setup(self: *cxmdb.API) !void {
    const csw: definitions.AP_MEM_CSW = .{
        .Size = 0b010,
        .ADDRINC = 0b01,
        .DEVICEEN = 1,
        .TRINPROG = 0,
        .MODE = 0,
        .TYPE = 0,
        .MTE = 0,
        .SPIDEN = 0,
        .PROT = 0x23,
        .DBGSWENABLE = 1,
    };

    try write_dap_reg(self, definitions.AP_MEM_CSW, csw);
}

fn read_mem_do(self: *cxmdb.API, addr: u32, buf: []u32) !u32 {
    while ((try read_dap_reg(self, definitions.AP_MEM_CSW)).TRINPROG != 0) {
        continue;
    }

    // try mem_setup(self);

    const tar: definitions.AP_MEM_TAR_LO = .{
        .ADDR = addr,
    };
    try write_dap_reg(self, @TypeOf(tar), tar);

    _ = try read_dap_reg(self, definitions.AP_MEM_DRW);

    for (0..buf.len - 1) |i| {
        buf[i] = (try read_dap_reg(self, definitions.AP_MEM_DRW)).DATA;
    }

    const readval = try read_dap_reg_as(self, definitions.RDBUFF, definitions.AP_MEM_DRW);
    buf[buf.len - 1] = readval.DATA;

    return @intCast(buf.len);
}

inline fn write_mem_do(self: *cxmdb.API, addr: u32, buf: []u32) u32 {
    const tar: definitions.AP_MEM_TAR_LO = .{
        .ADDR = addr,
    };
    write_dap_reg(self, @TypeOf(tar), tar);

    for (0..buf.len - 1) |i| {
        write_dap_reg(self, definitions.AP_MEM_DRW, buf[i]);
    }
    read_dap_reg(self, definitions.RDBUFF);
}

fn mem_op_do(self: *cxmdb.API, addr: u32, buf: []u32, fun: fn (self: *cxmdb.API, addr: u32, buf: []u32) anyerror!u32) !u32 {
    var current_ptr: u32 = 0;

    while ((buf.len - current_ptr) > 0) {
        const bytes_left: u32 = @min(0x400, @as(u32, @intCast(buf.len)) - current_ptr);
        const read_len = bytes_left - (current_ptr & 0x3FF);
        _ = try fun(self, current_ptr + addr, buf[current_ptr..(current_ptr + read_len)]);
        current_ptr = current_ptr + read_len;
    }
    return @intCast(buf.len);
}

pub fn read_mem(self: *cxmdb.API, addr: u32, buf: []u32) !u32 {
    return mem_op_do(self, addr, buf, read_mem_do);
}

pub fn read_mem_single(self: *cxmdb.API, addr: u32) !u32 {
    var buf: [1]u32 = undefined;
    _ = try mem_op_do(self, addr, &buf, read_mem_do);
    return buf[0];
}

pub fn write_mem(self: *cxmdb.API, addr: u32, buf: []u32) void {
    return mem_op_do(self, addr, buf, write_mem_do);
}

pub fn setup_connection(self: *cxmdb.API) !void {
    try self.vtable.swd.swd_reset(self);

    // Read and report DPIDR register to leave reset
    _ = try read_dap_reg(self, definitions.DPIDR);

    // Clear error flags
    _ = try self.vtable.swd.swd(self, .{ .APnDP = .DP, .RnW = .W, .A = .A00, .DATA = 0x0000001E });

    // Power up system and DP and Debug
    var ctrl_stat = try read_dap_reg(self, definitions.CTRL_STAT);
    ctrl_stat.CDBGPWRUPREQ = 1;
    ctrl_stat.CSYSPWRUPREQ = 1;
    ctrl_stat.ORUNDETECT = 1;
    try write_dap_reg(self, definitions.CTRL_STAT, ctrl_stat);

    while (ctrl_stat.CDBGPWRUPACK != 1) {
        ctrl_stat = try read_dap_reg(self, definitions.CTRL_STAT);
    }
}
