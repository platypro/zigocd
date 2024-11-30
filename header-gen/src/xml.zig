const std = @import("std");
const xml = @import("xml");

arena: std.heap.ArenaAllocator,
allocator: std.mem.Allocator,
root: ?*Element,

pub fn from_file(inner_allocator: std.mem.Allocator, path: []const u8) !@This() {
    var result: @This() = .{ .arena = std.heap.ArenaAllocator.init(inner_allocator), .allocator = undefined, .root = null };
    result.allocator = result.arena.allocator();
    const allocator = result.allocator;

    var current_element: ?*Element = null;
    var file = try std.fs.openFileAbsolute(path, .{});
    const reader = file.reader();
    var xml_doc = xml.streamingDocument(allocator, reader);
    defer xml_doc.deinit();
    var xml_reader = xml_doc.reader(allocator, .{});

    while (xml_reader.read()) |val| {
        switch (val) {
            .eof => break,
            .element_start => {
                const new_element = try allocator.create(Element);

                const element_name = xml_reader.elementNameNs();
                new_element.* = .{ .name = try allocator.dupe(u8, element_name.local) };

                if (current_element) |element| {
                    if (!element.children.contains(element_name.local)) {
                        try element.children.put(allocator, try allocator.dupe(u8, element_name.local), .empty);
                    }
                    var element_list = element.children.getPtr(element_name.local).?;
                    try element_list.append(allocator, new_element);
                    new_element.parent = element;
                }

                current_element = new_element;
                const number_of_attributes: u32 = @intCast(xml_reader.attributeCount());
                try current_element.?.attributes.ensureTotalCapacity(allocator, number_of_attributes);
                for (0..number_of_attributes) |i| {
                    try current_element.?.attributes.put(allocator, try allocator.dupe(u8, xml_reader.attributeName(i)), try allocator.dupe(u8, try xml_reader.attributeValue(i)));
                }
            },
            .element_end => {
                if (current_element) |element| {
                    if (element.parent) |parent| current_element = parent;
                }
            },
            else => continue,
        }
    } else |err| {
        return err;
    }

    if (current_element) |el| {
        while (el.parent) |parent| current_element = parent;
        result.root = el;
    }

    return result;
}

pub fn deinit(self: @This()) void {
    self.arena.deinit();
}

pub const Element = struct {
    name: []const u8,
    attributes: std.StringHashMapUnmanaged([]const u8) = .empty,
    children: std.StringArrayHashMapUnmanaged(std.ArrayListUnmanaged(*Element)) = .empty,
    parent: ?*Element = null,

    pub const Iterator = struct {
        list: ?std.ArrayListUnmanaged(*Element),
        current_index: u32,

        pub fn next(it: *Iterator) ?*Element {
            if (it.list) |list| {
                if (it.current_index >= list.items.len) {
                    return null;
                }

                const result = list.items[it.current_index];
                it.current_index += 1;
                return result;
            }
            return null;
        }

        pub fn prev(it: *Iterator) ?*Element {
            if (it.list) |list| {
                if (it.current_index == 0) {
                    return null;
                }

                it.current_index -= 1;
                return list.items[it.current_index];
            }
            return null;
        }
    };

    pub fn get_attribute(self: @This(), key: []const u8) ?[]const u8 {
        return self.attributes.get(key);
    }

    pub fn get_child(node: *Element, key: []const u8) ?*Element {
        if (node.children.get(key)) |sublist| {
            return sublist.items[0];
        } else {
            return null;
        }
    }

    pub fn iterate(node: *Element, key: []const u8) Iterator {
        return Iterator{
            .list = node.children.get(key) orelse null,
            .current_index = 0,
        };
    }
};
