const std = @import("std");
const HeaderGen = @import("HeaderGen.zig");
const xml = @import("xml.zig");

const atdf = @import("parser.atdf.zig");

const Error = error{UnableToDetermineType};

pub fn parse_file(allocator: std.mem.Allocator, path: [:0]const u8) !*HeaderGen {
    if (std.mem.endsWith(u8, path, ".atdf")) {
        return try atdf.parse_atdf(allocator, path);
    }
    return Error.UnableToDetermineType;
}
