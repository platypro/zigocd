const std = @import("std");

const Promise = @import("Promise.zig").Promise;

queue: [QueueSize]QueueItem,
mutex: std.Thread.Mutex = .{},
head: u32 = 0,
tail: u32 = 0,

const QueueSize = 5;

const QueueItemHdr = enum(usize) {
    none,
    init,
    read_reg,
    write_reg,
};
const QueueItem = struct {
    typ: QueueItemHdr,
    val1: u32,
    val2: u32,
    promise: Promise(u32),
};

const QueueError = error{
    QueueFull,
};

pub fn init(allocator: std.mem.Allocator) !@This() {
    var result: @This() = undefined;
    result.head = 0;
    result.tail = 0;
    result.mutex = .{};

    for (&result.queue) |*item| {
        item.val1 = 0;
        item.val2 = 0;
        item.typ = .none;
        item.promise = try Promise(u32).init(allocator);
    }

    return result;
}

pub fn push(self: *@This(), typ: QueueItemHdr, val1: u32, val2: u32) !Promise(u32) {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.tail == ((self.head + 1) % QueueSize)) return QueueError.QueueFull;

    self.queue[self.head].typ = typ;
    self.queue[self.head].val1 = val1;
    self.queue[self.head].val2 = val2;

    const result = self.queue[self.head].promise;
    self.head = ((self.head + 1) % QueueSize);
    return result;
}

pub fn pop(self: *@This()) ?QueueItem {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.head == self.tail) {
        return null;
    }

    const result = self.queue[self.tail];
    self.tail = ((self.tail + 1) % QueueSize);

    return result;
}
