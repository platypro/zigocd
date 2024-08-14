pub const name = .samd51;

pub fn init(node: *cxmdb.Node) !void {
    _ = node;
}

pub fn deinit(node: *cxmdb.Node) void {
    _ = node;
}

const std = @import("std");
const cxmdb = @import("../libcxmdb.zig");

pub fn connect(self: *cxmdb.Node) !void {
    if (self.transport == null) return;
    if (self.transport.?.type == .swd) {
        try cxmdb.API.getClass(.swd).setup_connection(self.transport.?);
        _ = try cxmdb.API.getClass(.swd).query_aps(self.transport.?);
    }
}
