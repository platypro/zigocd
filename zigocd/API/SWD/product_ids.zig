const std = @import("std");

// These product IDs were taken from openocd from file src/target/arm_adi_v5.c

pub const CoresightId = struct {
    manufacturer: u12,
    product: u12,
    name: []const u8,
};

fn generate_coresight_ids() ![]const CoresightId {
    const csv_src = @embedFile("product_ids.csv");
    var result: []const CoresightId = &.{};

    var entry_iter = std.mem.splitAny(u8, csv_src, "\n");
    while (entry_iter.next()) |entry| {
        @setEvalBranchQuota(csv_src.len * 8);
        var element: CoresightId = undefined;
        var field_iter = std.mem.splitAny(u8, entry, ",\n");
        element.manufacturer = std.fmt.parseInt(u16, field_iter.next().?, 0) catch break;
        element.product = std.fmt.parseInt(u16, field_iter.next().?, 0) catch break;
        element.name = field_iter.next() orelse break;

        result = result ++ [_]CoresightId{element};
    }

    return result;
}

pub const ids: []const CoresightId = generate_coresight_ids() catch @compileError("Couldnt generate coresight ids");
