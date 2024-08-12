pub const name = .samd51;

pub fn init(node: *cxmdb.Node) !void {
    _ = node;
}

pub fn deinit(node: *cxmdb.Node) void {
    _ = node;
}

const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");

// pub fn connect(self: *@This()) void {

// }
