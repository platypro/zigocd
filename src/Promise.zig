const std = @import("std");

const Error = error{
    NotFulfilled,
};

pub fn Promise(comptime T: type) type {
    return struct {
        pub const HeapType = struct {
            value: ?T = null,
            sema: std.Thread.Semaphore = {},
            pub fn fulfill(self: *@This(), val: T) void {
                self.value = val;
                self.sema.post();
            }
        };

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
            self.heap.?.fulfill(val);
        }

        pub fn wait(self: *@This()) !T {
            if (self.heap == null) return Error.NotFulfilled;
            self.heap.?.sema.wait();
            const result = self.heap.?.value;
            self.allocator.destroy(self.heap.?);
            self.heap = null;
            return result.?;
        }

        pub fn poll(self: *@This()) !T {
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
