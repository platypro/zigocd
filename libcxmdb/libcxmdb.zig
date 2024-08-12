const std = @import("std");
pub const Node = @import("Node.zig");
pub const API = @import("API.zig");

pub const Handle = usize;
const DeviceQueue = @import("DeviceQueue.zig");

nodes: std.ArrayList(Node),
allocator: std.mem.Allocator,
cmd_queue_thread: std.Thread,
cmd_queue: DeviceQueue,
exit: c_int,

const node_cache = Node.node_cache;

pub const Error = error{
    NoUserData,
    AllocError,
    NoApi,
};

pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
    self.nodes = @TypeOf(self.nodes).init(allocator);
    self.allocator = allocator;
    _ = try self.spawnNode(.host);
}

pub fn spawnNode(self: *@This(), comptime typ: Node.node_enum) !*Node {
    var node = try self.nodes.addOne();
    try node.init(self.allocator, typ);

    return node;
}

pub fn getRootNode(self: *@This()) *Node {
    return &self.nodes.items[0];
}

pub fn deinit(self: *@This()) void {
    for (self.nodes.items) |*node| {
        node.deinit();
    }
    self.nodes.deinit();
}
