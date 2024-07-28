const std = @import("std");

pub fn Promise(comptime T: type) type {
    const HeapType = struct {
        value: ?T = null,
        sema: std.Thread.Semaphore = {},
    };
    return struct {
        allocator: std.mem.Allocator,
        heap: ?*HeapType = null,

        pub fn init(allocator: std.mem.Allocator) !@This() {
            const result = .{
                .allocator = allocator,
                .heap = try allocator.create(HeapType),
            };
            result.heap.value = null;
            result.heap.sema = .{};

            return result;
        }

        pub fn fulfill(self: @This(), val: T) void {
            if (self.heap == null) return;
            self.heap.?.value = val;
            self.heap.?.sema.post();
        }

        pub fn wait(self: *@This()) ?T {
            if (self.heap == null) return null;
            self.heap.?.sema.wait();
            const result = self.heap.?.value;
            self.allocator.destroy(self.heap.?);
            self.heap = null;
            return result.?;
        }

        pub fn poll(self: *@This()) ?T {
            if (self.heap == null) return null;
            if (self.heap.?.sema.permits > 0) {
                const result = self.heap.?.value;
                self.allocator.destroy(self.heap.?);
                self.heap = null;
                return result;
            } else return null;
        }

        pub fn discard(self: *@This()) void {
            self.allocator.destroy(self.heap.?);
            self.heap = null;
        }
    };
}
