const std = @import("std");
const Error = error{UndefinedToken};

allocator: std.mem.Allocator,
src: std.ArrayListUnmanaged(u8),

pub fn init(allocator: std.mem.Allocator, size: u64) !@This() {
    var result: @This() = .{
        .allocator = allocator,
        .src = std.ArrayListUnmanaged(u8).empty,
    };
    try result.src.ensureTotalCapacity(allocator, size);

    return result;
}

pub fn push_identifier(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
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

pub fn push_docstring(self: *@This(), str: []const u8) !void {
    try self.src.appendSlice(self.allocator, "\n///");
    try self.src.appendSlice(self.allocator, str);
    try self.src.appendSlice(self.allocator, "\n");
}

pub fn push_builtin(self: *@This(), comptime builtin: []const u8) !void {
    const str = "@" ++ builtin;
    try self.src.appendSlice(self.allocator, str);
}

pub fn push(self: *@This(), comptime tokens: []const std.zig.Token.Tag) !void {
    comptime var build: []const u8 = &.{};
    inline for (tokens) |token| {
        build = build ++ switch (token) {
            .keyword_struct => "struct",
            .keyword_union => "union",
            .keyword_const => "const ",
            .keyword_pub => "pub ",
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
            .ampersand => "&",
            .period => ".",
            else => return Error.UndefinedToken,
        };
    }
    try self.src.appendSlice(self.allocator, build);
}

/// +ve is unsigned, -ve is signed
pub fn push_int_type(self: *@This(), is_signed: enum { signed, unsigned }, num: u64) !void {
    const val = try std.fmt.allocPrint(self.allocator, "{s}{}", .{ if (is_signed == .unsigned) "u" else "i", num });
    defer self.allocator.free(val);
    try self.src.appendSlice(self.allocator, val);
}

pub fn push_int(self: *@This(), value: u64) !void {
    try self.src.appendSlice(self.allocator, "0x");
    try std.fmt.formatInt(value, 16, .upper, .{}, self.src.writer(self.allocator));
}

pub fn push_int_dec(self: *@This(), value: u64) !void {
    try std.fmt.formatInt(value, 10, .upper, .{}, self.src.writer(self.allocator));
}

pub fn push_string_literal(self: *@This(), value: []const u8) !void {
    try self.push_identifier("\"{s}\"", .{value});
}

pub fn render(self: *@This()) ![]const u8 {
    try self.src.append(self.allocator, 0);

    // return self.src.items;
    var ast = try std.zig.Ast.parse(self.allocator, self.src.items[0 .. self.src.items.len - 1 :0], .zig);
    defer ast.deinit(self.allocator);
    for (ast.errors) |@"error"| {
        std.debug.print("Error: {}\n", .{@"error".tag});
    }
    if (ast.errors.len == 0) {
        const result = try ast.render(self.allocator);
        self.src.clearAndFree(self.allocator);
        return result;
    } else return self.src.toOwnedSlice(self.allocator);
}
