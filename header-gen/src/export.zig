const std = @import("std");
const HeaderGen = @import("HeaderGen.zig");

const Renderer = struct {
    const Error = error{UndefinedToken};

    allocator: std.mem.Allocator,
    src: std.ArrayListUnmanaged(u8),

    fn init(allocator: std.mem.Allocator, size: u64) !@This() {
        var result: @This() = .{
            .allocator = allocator,
            .src = std.ArrayListUnmanaged(u8).empty,
        };
        try result.src.ensureTotalCapacity(allocator, size);

        return result;
    }

    fn push_identifier(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
        const old_size = self.src.items.len;
        const fmt_len = std.fmt.count(fmt, args);
        try self.src.ensureTotalCapacity(self.allocator, old_size + fmt_len + 3);
        self.src.items.len = old_size + fmt_len + 3;
        _ = try std.fmt.bufPrint(self.src.items[(old_size + 2)..], fmt, args);

        if (std.ascii.isDigit(self.src.items[(old_size + 2)])) {
            self.src.items[old_size] = '@';
            self.src.items[old_size + 1] = '"';
            self.src.items[old_size + fmt_len + 2] = '"';
        } else {
            self.src.items[old_size] = ' ';
            self.src.items[old_size + 1] = ' ';
            self.src.items[old_size + fmt_len + 2] = ' ';
        }
    }

    fn push_docstring(self: *@This(), str: []const u8) !void {
        try self.src.appendSlice(self.allocator, "\n///");
        try self.src.appendSlice(self.allocator, str);
        try self.src.appendSlice(self.allocator, "\n");
    }

    fn push_builtin(self: *@This(), comptime builtin: []const u8) !void {
        const str = "@" ++ builtin;
        try self.src.appendSlice(self.allocator, str);
    }

    fn push(self: *@This(), comptime tokens: []const std.zig.Token.Tag) !void {
        comptime var build: []const u8 = &.{};
        inline for (tokens) |token| {
            build = build ++ switch (token) {
                .keyword_struct => "struct",
                .keyword_union => "union",
                .keyword_const => "const ",
                .keyword_enum => "enum",
                .keyword_packed => "packed ",
                .keyword_align => "align",
                .equal => " = ",
                .l_brace => "{",
                .r_brace => "}",
                .l_paren => "(",
                .r_paren => ")",
                .l_bracket => "[",
                .r_bracket => "] ",
                .semicolon => ";\n",
                .colon => ":",
                .comma => ",",
                .asterisk => "*",
                else => return Error.UndefinedToken,
            };
        }
        try self.src.appendSlice(self.allocator, build);
    }

    /// +ve is unsigned, -ve is signed
    fn push_int_type(self: *@This(), is_signed: enum { signed, unsigned }, num: u64) !void {
        const val = try std.fmt.allocPrint(self.allocator, "{s}{}", .{ if (is_signed == .unsigned) "u" else "i", num });
        defer self.allocator.free(val);
        try self.src.appendSlice(self.allocator, val);
    }

    fn push_int(self: *@This(), value: u64) !void {
        try self.src.appendSlice(self.allocator, "0x");
        try std.fmt.formatInt(value, 16, .upper, .{}, self.src.writer(self.allocator));
    }

    fn push_int_dec(self: *@This(), value: u64) !void {
        try std.fmt.formatInt(value, 10, .upper, .{}, self.src.writer(self.allocator));
    }

    fn push_string_literal(self: *@This(), value: []const u8) !void {
        try self.push_identifier("\"{s}\"", .{value});
    }

    fn render(self: *@This()) ![]const u8 {
        try self.src.append(self.allocator, 0);

        // return self.src.items;
        var ast = try std.zig.Ast.parse(self.allocator, self.src.items[0 .. self.src.items.len - 1 :0], .zig);
        defer ast.deinit(self.allocator);
        if (ast.errors.len == 0) {
            const result = try ast.render(self.allocator);
            self.src.clearAndFree(self.allocator);
            return result;
        } else return self.src.toOwnedSlice(self.allocator);
    }
};

pub fn write_enum(renderer: *Renderer, header_gen: *HeaderGen, enu: HeaderGen.Enum) !void {
    try renderer.push(&.{.keyword_const});
    try renderer.push_identifier("{s}", .{header_gen.deintern(enu.name).?});
    try renderer.push(&.{ .equal, .keyword_enum, .l_paren });
    try renderer.push_int_type(.unsigned, enu.size);
    try renderer.push(&.{ .r_paren, .l_brace });

    for (enu.fields.items) |field| {
        if (field.description) |desc| try renderer.push_docstring(desc);
        try renderer.push_identifier("{s}", .{header_gen.deintern(field.name).?});
        try renderer.push(&.{.equal});
        try renderer.push_int(field.value);
        try renderer.push(&.{.comma});
    }
    try renderer.push(&.{ .r_brace, .semicolon });
}

pub fn write_struct(renderer: *Renderer, header_gen: *HeaderGen, peripheral: HeaderGen.Peripheral, struc: HeaderGen.Struct, is_base: bool) !void {
    if (!is_base) {
        try renderer.push(&.{.keyword_const});
        try renderer.push_identifier("__{s}", .{header_gen.deintern(struc.name).?});
        try renderer.push(&.{ .equal, .keyword_packed, .keyword_struct, .l_brace });
    }

    var walking_size: u64 = 0;
    var reserved_cnt: u32 = 0;
    for (struc.fields.items) |register_or_array| {
        if (register_or_array.offset > walking_size) {
            const reserved_size = register_or_array.offset - walking_size;
            try renderer.push_identifier("RESERVED{}", .{reserved_cnt});
            try renderer.push(&.{ .colon, .l_bracket });
            try renderer.push_int(reserved_size);
            try renderer.push(&.{.r_bracket});
            try renderer.push_int_type(.unsigned, 8);
            try renderer.push(&.{.comma});
            walking_size = register_or_array.offset;
            reserved_cnt += 1;
        }

        if (register_or_array.description) |desc| try renderer.push_docstring(desc);
        try renderer.push_identifier("{s}", .{header_gen.deintern(register_or_array.name).?});
        switch (register_or_array.data) {
            .Register => {
                try renderer.push(&.{.colon});
                try renderer.push_identifier("_{s}", .{header_gen.deintern(register_or_array.name).?});
                walking_size = register_or_array.data.Register.size + register_or_array.offset;
            },
            .Array => {
                try renderer.push(&.{.colon});
                if (register_or_array.data.Array.num > 0) {
                    try renderer.push(&.{.l_bracket});
                    try renderer.push_int(register_or_array.data.Array.num);
                    try renderer.push(&.{.r_bracket});
                }
                try renderer.push_identifier("__{s}", .{header_gen.deintern(peripheral.find_struct(register_or_array.data.Array.backing_struct).?.name).?});

                walking_size = register_or_array.offset + (register_or_array.data.Array.increment * register_or_array.data.Array.num);
            },
        }
        try renderer.push(&.{.comma});
    }

    for (struc.fields.items) |register_or_array| {
        if (register_or_array.data == .Array) {
            continue;
        }

        walking_size = 0;
        reserved_cnt = 0;
        try renderer.push(&.{.keyword_const});
        try renderer.push_identifier("_{s}", .{header_gen.deintern(register_or_array.name).?});
        try renderer.push(&.{ .equal, .keyword_packed, .keyword_struct, .l_brace });
        for (register_or_array.data.Register.fields.items) |reg_field| {
            if (reg_field.offset > walking_size) {
                const reserved_size = reg_field.offset - walking_size;
                try renderer.push_identifier("RESERVED{}", .{reserved_cnt});
                try renderer.push(&.{.colon});
                try renderer.push_int_type(.unsigned, reserved_size);
                try renderer.push(&.{.comma});
                walking_size = reg_field.offset;
                reserved_cnt += 1;
            }

            if (reg_field.description) |desc| try renderer.push_docstring(desc);
            try renderer.push_identifier("{s}", .{header_gen.deintern(reg_field.name).?});
            try renderer.push(&.{.colon});

            switch (reg_field.type) {
                .unsigned => {
                    walking_size += reg_field.type.unsigned;
                    try renderer.push_int_type(.unsigned, reg_field.type.unsigned);
                },
                .enumeration => {
                    const enum_name = reg_field.type.enumeration;
                    if (peripheral.find_enum(enum_name)) |name| {
                        walking_size += name.size;
                    } else std.log.warn("Enum {s} is not available! The resulting zig code will not compile.", .{header_gen.deintern(enum_name).?});
                    try renderer.push_identifier("{s}", .{header_gen.deintern(enum_name).?});
                },
            }
            try renderer.push(&.{.comma});
        }
        if (walking_size < register_or_array.data.Register.size) {
            const reserved_size = register_or_array.data.Register.size - walking_size;
            try renderer.push_identifier("RESERVED{}", .{reserved_cnt});
            try renderer.push(&.{.colon});
            try renderer.push_int_type(.unsigned, reserved_size);
            try renderer.push(&.{.comma});
        }
        try renderer.push(&.{ .r_brace, .semicolon });
    }
    if (!is_base) {
        try renderer.push(&.{ .r_brace, .semicolon });
    }
}

fn write_string_value(renderer: *Renderer, name: []const u8, value: []const u8) !void {
    try renderer.push(&.{.keyword_const});
    try renderer.push_identifier("{s}", .{name});
    try renderer.push(&.{.equal});
    try renderer.push_string_literal(value);
    try renderer.push(&.{.semicolon});
}

pub fn export_zig(header_gen: *HeaderGen) ![]const u8 {
    var renderer = try Renderer.init(header_gen.allocator, header_gen.guestimated_size);

    try header_gen.sort();

    for (header_gen.peripherals.items) |peripheral| {
        if (peripheral.description) |desc| try renderer.push_docstring(desc);
        try renderer.push(&.{.keyword_const});
        try renderer.push_identifier("_{s}", .{header_gen.deintern(peripheral.name).?});
        if (peripheral.is_union) {
            try renderer.push(&.{ .equal, .keyword_packed, .keyword_union, .l_brace });
        } else {
            try renderer.push(&.{ .equal, .keyword_packed, .keyword_struct, .l_brace });
        }

        try write_struct(&renderer, header_gen, peripheral, peripheral.base_struct, true);

        for (peripheral.enums.items) |enu| {
            try write_enum(&renderer, header_gen, enu);
        }

        for (peripheral.structs.items) |struc| {
            try write_struct(&renderer, header_gen, peripheral, struc, false);
        }

        try renderer.push(&.{ .r_brace, .semicolon });
    }

    for (header_gen.devices.items) |device| {
        for (device.peripheral_instances.items) |*peripheral_instance| {
            try renderer.push(&.{.keyword_const});
            try renderer.push_identifier("{s}", .{header_gen.deintern(peripheral_instance.name).?});
            try renderer.push(&.{ .colon, .asterisk });
            var build_id = std.ArrayList(u8).init(header_gen.allocator);
            defer build_id.deinit();
            var num_underscores: u32 = 1;
            while (peripheral_instance.typ.popOrNull()) |typ| {
                try build_id.appendNTimes('_', num_underscores);
                try build_id.appendSlice(header_gen.deintern(typ).?);
                if (peripheral_instance.typ.items.len > 0)
                    try build_id.append('.');
                num_underscores += 1;
            }
            try renderer.push_identifier("{s}", .{build_id.items});
            try renderer.push(&.{.equal});
            try renderer.push_builtin("ptrFromInt");
            try renderer.push(&.{.l_paren});
            try renderer.push_int(peripheral_instance.offset);
            try renderer.push(&.{ .r_paren, .semicolon });
        }

        try write_string_value(&renderer, "DEVICE_NAME", header_gen.deintern(device.name).?);
        if (device.description) |val| try write_string_value(&renderer, "DEVICE_DESCRIPTION", val);
        if (device.vendor) |val| try write_string_value(&renderer, "DEVICE_VENDOR", val);
        if (device.family) |val| try write_string_value(&renderer, "DEVICE_FAMILY", val);
        try write_string_value(&renderer, "DEVICE_ARCH", @tagName(device.arch));
    }

    return renderer.render();
}
