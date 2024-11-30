const std = @import("std");

allocator: std.mem.Allocator,
current_intern: InternId,
interns: std.StringHashMapUnmanaged(InternId),
peripherals: List(Peripheral),
devices: List(Device),
guestimated_size: u64,

const HeaderGen = @This();
const List = std.ArrayListUnmanaged;

pub fn new(allocator: std.mem.Allocator) !*@This() {
    const result = try allocator.create(@This());
    result.* = .{
        .allocator = allocator,
        .current_intern = 0,
        .interns = std.StringHashMapUnmanaged(InternId).empty,
        .peripherals = List(Peripheral).empty,
        .devices = List(Device).empty,
        .guestimated_size = 0,
    };
    return result;
}

pub fn deinit(self: *@This()) void {
    var keys = self.interns.keyIterator();
    while (keys.next()) |key| {
        self.allocator.free(key.*);
    }
    self.interns.clearAndFree(self.allocator);

    for (self.peripherals.items) |*peripheral| peripheral.deinit(self.allocator);
    for (self.devices.items) |*device| device.deinit(self.allocator);

    self.peripherals.clearAndFree(self.allocator);
    self.devices.clearAndFree(self.allocator);

    self.allocator.destroy(self);
}

pub fn add_peripheral(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*Peripheral {
    const result = try self.peripherals.addOne(header_gen.allocator);
    result.description = null;
    result.name = try header_gen.intern(name);
    result.enums = List(Enum).empty;
    result.structs = List(Struct).empty;
    result.base_struct = Struct{};

    return result;
}

pub fn find_peripheral(self: *@This(), name: InternId) ?*Peripheral {
    for (self.peripherals.items) |*peripheral| {
        if (peripheral.name == name) {
            return peripheral;
        }
    }
    return null;
}

pub fn add_device(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*Device {
    const result = try self.devices.addOne(header_gen.allocator);
    result.name = try header_gen.intern(name);
    result.description = null;
    result.vendor = null;
    result.family = null;
    result.arch = .unknown;
    result.interrupts = List(Interrupt).empty;
    result.peripheral_instances = List(PeripheralInstance).empty;

    return result;
}

pub fn intern(self: *@This(), str: []const u8) !InternId {
    if (self.interns.get(str)) |id| {
        return id;
    } else {
        try self.interns.put(self.allocator, try self.allocator.dupe(u8, str), self.current_intern);
        self.current_intern += 1;
        return self.current_intern - 1;
    }
}

pub fn deintern(self: *@This(), id: InternId) ?[]const u8 {
    var iterator = self.interns.iterator();
    while (iterator.next()) |entry| {
        if (entry.value_ptr.* == id) {
            return entry.key_ptr.*;
        }
    }
    return null;
}

pub fn sort(self: *@This()) !void {
    for (self.peripherals.items) |peripheral| {
        std.sort.insertion(StructField, peripheral.base_struct.fields.items, {}, StructField.cmp);
        for (peripheral.structs.items) |struc| {
            std.sort.insertion(StructField, struc.fields.items, {}, StructField.cmp);

            for (struc.fields.items) |field| {
                switch (field.data) {
                    .Register => {
                        std.sort.insertion(RegisterField, field.data.Register.fields.items, {}, RegisterField.cmp);
                    },
                    .Array => {},
                }
            }
        }
    }
}

pub const InternId = u32;

pub const Device = struct {
    name: InternId,
    description: ?[]const u8,
    vendor: ?[]const u8,
    family: ?[]const u8,
    arch: Arch,
    interrupts: List(Interrupt),
    peripheral_instances: List(PeripheralInstance),

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.description) |description| allocator.free(description);
        if (self.vendor) |vendor| allocator.free(vendor);
        if (self.family) |family| allocator.free(family);
        for (self.interrupts.items) |item| {
            if (item.description) |description| allocator.free(description);
        }
        self.interrupts.clearAndFree(allocator);
        for (self.peripheral_instances.items) |*instance| {
            instance.typ.clearAndFree(allocator);
        }
        self.peripheral_instances.clearAndFree(allocator);
    }

    pub fn add_interrupt(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*Interrupt {
        var interrupt = try self.interrupts.addOne(header_gen.allocator);
        interrupt.name = try header_gen.intern(name);
        interrupt.description = null;
        interrupt.index = 0;

        return interrupt;
    }

    pub fn add_peripheral_instance(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*PeripheralInstance {
        var result = try self.peripheral_instances.addOne(header_gen.allocator);
        result.name = try header_gen.intern(name);
        result.offset = 0;
        result.typ = @TypeOf(result.typ).empty;

        return result;
    }
};

pub const Peripheral = struct {
    name: InternId,
    description: ?[]const u8,
    is_union: bool = false,
    base_struct: Struct,
    structs: List(Struct),
    enums: List(Enum),

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.description) |description| allocator.free(description);
        for (self.enums.items) |*@"enum"| {
            for (@"enum".fields.items) |field| {
                if (field.description) |description| allocator.free(description);
            }
            @"enum".fields.clearAndFree(allocator);
        }
        self.enums.clearAndFree(allocator);

        for (self.structs.items) |*@"struct"| @"struct".deinit(allocator);
        self.structs.clearAndFree(allocator);
        self.base_struct.deinit(allocator);
    }

    pub fn add_struct(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*Struct {
        var result = try self.structs.addOne(header_gen.allocator);
        result.* = std.mem.zeroes(Struct);

        result.fields = List(StructField).empty;
        result.name = try header_gen.intern(name);
        result.description = null;

        return result;
    }

    pub fn add_enum(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*Enum {
        var result = try self.enums.addOne(header_gen.allocator);
        result.name = try header_gen.intern(name);
        result.size = 0;
        result.fields = @TypeOf(result.fields).empty;

        return result;
    }

    pub fn find_enum(self: @This(), name: InternId) ?*Enum {
        for (self.enums.items) |*enu| {
            if (enu.name == name) {
                return enu;
            }
        }
        return null;
    }

    pub fn find_struct(self: @This(), name: InternId) ?*Struct {
        for (self.structs.items) |*struc| {
            if (struc.name == name) {
                return struc;
            }
        }
        return null;
    }
};

pub const Struct = struct {
    name: InternId = 0,
    description: ?[]const u8 = null,
    fields: List(StructField) = List(StructField).empty,
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.description) |description| allocator.free(description);

        for (self.fields.items) |*field| {
            if (field.description) |description| allocator.free(description);

            if (std.meta.activeTag(field.data) == .Register) {
                for (field.data.Register.fields.items) |item| {
                    if (item.description) |description| allocator.free(description);
                }
                field.data.Register.fields.clearAndFree(allocator);
            }
        }
        self.fields.clearAndFree(allocator);
    }
    pub fn add_register(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*StructField {
        var result = try self.fields.addOne(header_gen.allocator);
        result.name = try header_gen.intern(name);
        result.description = null;
        result.offset = 0;
        result.data = .{
            .Register = .{
                .size = 0,
                .fields = List(RegisterField).empty,
                .reset_value = 0,
            },
        };

        return result;
    }

    pub fn add_array(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*StructField {
        var result = try self.fields.addOne(header_gen.allocator);
        result.name = try header_gen.intern(name);
        result.description = null;
        result.offset = 0;
        result.data = .{
            .Array = .{
                .num = 0,
                .increment = 0,
                .backing_struct = 0,
            },
        };

        return result;
    }
};

pub const StructField = struct {
    name: InternId,
    description: ?[]const u8,
    offset: u64,

    data: union(FieldType) {
        Register: struct {
            size: u64,
            reset_value: u64,
            fields: List(RegisterField),
        },
        Array: struct {
            num: u64,
            increment: u64,
            backing_struct: InternId,
        },
    },

    const FieldType = enum {
        Register,
        Array,
    };

    pub fn cmp(ctx: void, lhs: @This(), rhs: @This()) bool {
        _ = ctx;
        return lhs.offset < rhs.offset;
    }

    pub fn add_field(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*RegisterField {
        var field = try self.data.Register.fields.addOne(header_gen.allocator);
        field.name = try header_gen.intern(name);
        field.description = null;
        field.offset = 0;
        field.type = .{ .unsigned = 0 };

        return field;
    }
};

pub const RegisterField = struct {
    name: InternId,
    description: ?[]const u8,

    offset: u32,
    type: union(enum) {
        enumeration: InternId,
        unsigned: u32,
    },

    pub fn cmp(ctx: void, lhs: @This(), rhs: @This()) bool {
        _ = ctx;
        return lhs.offset < rhs.offset;
    }
};

pub const Enum = struct {
    name: InternId,
    size: u32,
    fields: List(EnumField),

    pub fn add_field(self: *@This(), header_gen: *HeaderGen, name: []const u8) !*EnumField {
        var field = try self.fields.addOne(header_gen.allocator);
        field.* = std.mem.zeroes(EnumField);
        field.name = try header_gen.intern(name);

        return field;
    }

    pub fn has_field(self: *@This(), name: InternId) bool {
        for (self.fields.items) |item| {
            if (item.name == name) {
                return true;
            }
        }
        return false;
    }
};

pub const EnumField = struct {
    name: InternId,
    description: ?[]const u8,
    value: u64,
};

pub const PeripheralInstance = struct {
    name: InternId,
    offset: u64,
    typ: List(InternId),
};

pub const Interrupt = struct {
    name: InternId,
    description: ?[]const u8,
    index: i32,
};

pub const Arch = enum {
    unknown,
    cortex_m4,
    avr8,
    avr8x,
};
