const std = @import("std");
const HeaderGen = @import("HeaderGen.zig");
const xml = @import("xml.zig");

const Error = error{ BadElement, NoName };

fn get_attribute(node: *xml.Element, value: [:0]const u8) ![]const u8 {
    return node.get_attribute(value) orelse Error.BadElement;
}

fn add_register(result: *HeaderGen, peripheral: *HeaderGen.Peripheral, struc: *HeaderGen.Struct, register_elem: *xml.Element, mode: ?[]const u8) !void {
    var name_is_allocated = false;
    var register_name = register_inst: {
        if (mode != null) {
            const concatenated_name = try std.fmt.allocPrint(result.allocator, "{s}_{s}", .{ try get_attribute(register_elem, "name"), mode.? });
            name_is_allocated = true;
            break :register_inst concatenated_name;
        } else {
            break :register_inst try get_attribute(register_elem, "name");
        }
    };
    const register_name_intern = try result.intern(register_name);
    if (register_name_intern == struc.name or register_name_intern == peripheral.name) {
        const old_name = register_name;
        register_name = try std.fmt.allocPrint(result.allocator, "__{s}", .{old_name});
        if (name_is_allocated == true) result.allocator.free(register_name);
        name_is_allocated = true;
    }
    var register = try struc.add_register(result, register_name);
    if (name_is_allocated == true) result.allocator.free(register_name);

    if (register_elem.get_attribute("caption")) |caption| {
        register.description = try result.allocator.dupe(u8, caption);
    }
    register.offset = try std.fmt.parseInt(u64, try get_attribute(register_elem, "offset"), 0) << 3;
    register.data.Register.size = try std.fmt.parseInt(u64, try get_attribute(register_elem, "size"), 0) << 3;
    if (register_elem.get_attribute("initval")) |initval| {
        register.data.Register.reset_value = try std.fmt.parseInt(u64, initval, 0);
    }

    var field_iterator = register_elem.iterate("bitfield");
    loop: while (field_iterator.next()) |field_elem| {
        // Skip field if mode exists and does not match
        if (mode) |mode_name| {
            if (field_elem.get_attribute("modes")) |mode_cmp| {
                if (!std.mem.eql(u8, mode_cmp, mode_name)) continue :loop;
            }
        }

        var name_str = try get_attribute(field_elem, "name");
        const name_num_opt = search_for_same_name(field_iterator, name_str);
        if (name_num_opt) |name_num| {
            name_str = try std.fmt.allocPrint(result.allocator, "{s}{}", .{ name_str, name_num });
            name_is_allocated = true;
        }

        var field = try register.add_field(result, name_str);
        if (name_is_allocated) result.allocator.free(name_str);

        if (field_elem.get_attribute("caption")) |caption| {
            field.description = try result.allocator.dupe(u8, caption);
        }

        const mask = try std.fmt.parseInt(u64, try get_attribute(field_elem, "mask"), 0);
        field.offset = @ctz(mask);
        if (field_elem.get_attribute("values")) |values| {
            field.type = .{ .enumeration = try result.intern(values) };
        } else {
            field.type = .{ .unsigned = @popCount(mask) };
        }
    }
}

fn add_struct(result: *HeaderGen, peripheral: *HeaderGen.Peripheral, struc: *HeaderGen.Struct, struct_elem: *xml.Element, mode: ?[]const u8) !void {
    if (struct_elem.get_attribute("caption")) |caption| {
        struc.description = try result.allocator.dupe(u8, caption);
    }

    // Create registers
    var register_iterator = struct_elem.iterate("register");
    loop: while (register_iterator.next()) |register_elem| {
        // Skip register if mode exists and does not match
        if (mode) |mode_name| {
            if (register_elem.get_attribute("modes")) |mode_cmp| {
                if (!std.mem.eql(u8, mode_cmp, mode_name)) continue :loop;
            }
        }

        var mode_iterator = register_elem.iterate("mode");
        var has_modes = false;
        while (mode_iterator.next()) |mode_elem| {
            try add_register(result, peripheral, struc, register_elem, try get_attribute(mode_elem, "name"));
            has_modes = true;
        }
        if (has_modes == false) {
            try add_register(result, peripheral, struc, register_elem, null);
        }
    }

    // Create arrays
    var array_iterator = struct_elem.iterate("register-group");
    loop: while (array_iterator.next()) |array_elem| {
        // Skip array if mode exists and does not match
        if (mode) |mode_name| {
            if (array_elem.get_attribute("modes")) |mode_cmp| {
                if (!std.mem.eql(u8, mode_cmp, mode_name)) continue :loop;
            }
        }

        var array = try struc.add_array(result, try get_attribute(array_elem, "name"));

        if (array_elem.get_attribute("caption")) |caption| array.description = try result.allocator.dupe(u8, caption);

        array.offset = try std.fmt.parseInt(u64, try get_attribute(array_elem, "offset"), 0);
        array.data.Array.backing_struct = try result.intern(try get_attribute(array_elem, "name-in-module"));
        array.data.Array.increment = try std.fmt.parseInt(u64, try get_attribute(array_elem, "size"), 0);
        array.data.Array.num = try std.fmt.parseInt(u64, try get_attribute(array_elem, "count"), 0);
    }
}

fn search_for_same_name(iterator: xml.Element.Iterator, name: []const u8) ?u32 {
    var count: u32 = 0;
    // Search previous nodes
    var prev_iterator = iterator;
    while (prev_iterator.prev()) |elem| {
        if (std.mem.eql(u8, elem.get_attribute("name").?, name)) {
            count += 1;
        }
    }

    //If no nodes found, see if there are forward nodes. If so, this has id 0
    var next_iterator = iterator;
    if (count == 0) {
        while (next_iterator.next()) |elem| {
            if (std.mem.eql(u8, elem.get_attribute("name").?, name)) {
                return 0;
            }
        }
        return null;
    }

    return count;
}

pub fn parse_atdf(allocator: std.mem.Allocator, path: [:0]const u8) !*HeaderGen {
    var result = try HeaderGen.new(allocator);
    var file = try std.fs.openFileAbsolute(path, .{});
    result.guestimated_size = (try file.stat()).size >> 2;
    file.close();

    const src_xml_opt = try xml.from_file(allocator, path);

    if (src_xml_opt.root == null) {
        return result;
    }
    const root = src_xml_opt.root.?;

    defer src_xml_opt.deinit();

    if (!std.mem.eql(u8, root.name, "avr-tools-device-file")) {
        return Error.BadElement;
    }

    const modules_elem = root.get_child("modules");
    if (modules_elem == null) {
        return Error.BadElement;
    }

    var module_iterator = modules_elem.?.iterate("module");
    while (module_iterator.next()) |module_elem| {
        var peripheral = try result.add_peripheral(result, try get_attribute(module_elem, "name"));

        // Grab name and description
        peripheral.name = try result.intern(try get_attribute(module_elem, "name"));
        if (module_elem.get_attribute("caption")) |description| {
            peripheral.description = try allocator.dupe(u8, description);
        }

        // Create enums
        var enum_iterator = module_elem.iterate("value-group");
        while (enum_iterator.next()) |enum_elem| {
            var enu = try peripheral.add_enum(result, try get_attribute(enum_elem, "name"));
            var enum_field_iterator = enum_elem.iterate("value");
            while (enum_field_iterator.next()) |enum_field_elem| {
                var name_str = try get_attribute(enum_field_elem, "name");
                var name_is_allocated = false;

                const name_num_opt = search_for_same_name(enum_field_iterator, name_str);
                if (name_num_opt) |name_num| {
                    name_str = try std.fmt.allocPrint(result.allocator, "{s}{}", .{ name_str, name_num });
                    name_is_allocated = true;
                }

                const enum_field = try enu.add_field(result, name_str);

                if (name_is_allocated) allocator.free(name_str);

                if (enum_field_elem.get_attribute("caption")) |caption| {
                    enum_field.description = try allocator.dupe(u8, caption);
                }
                const value_str = try get_attribute(enum_field_elem, "value");
                enum_field.value = try std.fmt.parseInt(u64, value_str, 0);
                enu.size = @max(enu.size, 64 - @clz(enum_field.value));
            }
        }

        // Create structs
        var struct_iterator = module_elem.iterate("register-group");
        while (struct_iterator.next()) |struct_elem| {
            const name_intern = try result.intern(try get_attribute(struct_elem, "name"));
            const is_base = (name_intern == peripheral.name);

            // Iterate "Modes" which provides variants of this struct
            var has_modes = false;
            var mode_iterator = struct_elem.iterate("mode");
            _ = mode_iterator.next();
            const second = mode_iterator.next();
            if (second != null) {
                mode_iterator = struct_elem.iterate("mode");

                while (mode_iterator.next()) |mode| {
                    const concatenated_name = try std.fmt.allocPrint(result.allocator, "{s}_{s}", .{ try get_attribute(struct_elem, "name"), try get_attribute(mode, "name") });
                    defer result.allocator.free(concatenated_name);

                    const new_struct = try peripheral.add_struct(result, concatenated_name);

                    if (is_base) {
                        // Has modes AND is a base struct, so we need to also instantiate them
                        peripheral.is_union = true;
                        var array = try peripheral.base_struct.add_array(result, concatenated_name);
                        array.offset = 0;
                        array.data.Array.backing_struct = new_struct.name;
                        array.data.Array.num = 0;
                    }

                    try add_struct(
                        result,
                        peripheral,
                        new_struct,
                        struct_elem,
                        try get_attribute(mode, "name"),
                    );

                    has_modes = true;
                }
            }
            if (has_modes == false) {
                if (is_base) {
                    try add_struct(result, peripheral, &peripheral.base_struct, struct_elem, null);
                } else {
                    try add_struct(
                        result,
                        peripheral,
                        try peripheral.add_struct(result, try get_attribute(struct_elem, "name")),
                        struct_elem,
                        null,
                    );
                }
            }
        }
    }

    // Devices
    var devices_elem = root.get_child("devices");
    var device_iterator = devices_elem.?.iterate("device");
    while (device_iterator.next()) |device_elem| {
        var device = try result.add_device(result, try get_attribute(device_elem, "name"));
        if (device_elem.get_attribute("architecture")) |arch| {
            if (std.mem.eql(u8, arch, "CORTEX-M4")) {
                device.arch = .cortex_m4;
            }
            if (std.mem.eql(u8, arch, "AVR8")) {
                device.arch = .avr8;
            }
            if (std.mem.eql(u8, arch, "AVR8X")) {
                device.arch = .avr8x;
            }
        }

        device.vendor = try result.allocator.dupe(u8, "Microchip Technology");
        if (device_elem.get_attribute("family")) |family| {
            device.family = try result.allocator.dupe(u8, family);
        }

        // Interrupts
        var interrupts_elem = device_elem.get_child("interrupts") orelse return Error.BadElement;
        var interrupt_iterator = interrupts_elem.iterate("interrupt");
        while (interrupt_iterator.next()) |interrupt_elem| {
            const value = interrupt_elem.get_attribute("value");
            if (value) |val| {
                var interrupt = try device.add_interrupt(result, try get_attribute(devices_elem.?, "name"));
                if (interrupt_elem.get_attribute("caption")) |caption| {
                    interrupt.description = try result.allocator.dupe(u8, caption);
                }
                interrupt.index = try std.fmt.parseInt(i32, val, 0);
            }
        }

        // Peripheral instances
        var peripherals_elem = device_elem.get_child("peripherals") orelse return Error.BadElement;
        var peripherals_iterator = peripherals_elem.iterate("module");
        while (peripherals_iterator.next()) |module_elem| {
            var instance_iterator = module_elem.iterate("instance");
            while (instance_iterator.next()) |instance_elem| {
                var register_group_iterator = instance_elem.iterate("register-group");
                while (register_group_iterator.next()) |register_group_elem| {
                    const register_group_name = try get_attribute(register_group_elem, "name");
                    const instance_name = try get_attribute(instance_elem, "name");
                    const module_name = try get_attribute(module_elem, "name");

                    const peripheral_instance = try device.add_peripheral_instance(result, register_group_name);
                    peripheral_instance.offset = try std.fmt.parseInt(u64, try get_attribute(register_group_elem, "offset"), 0);

                    try peripheral_instance.typ.append(result.allocator, try result.intern(try get_attribute(register_group_elem, "name-in-module")));
                    if (!std.mem.eql(u8, register_group_name, instance_name)) {
                        try peripheral_instance.typ.append(result.allocator, try result.intern(instance_name));
                    }
                    if (!std.mem.eql(u8, module_name, instance_name)) {
                        try peripheral_instance.typ.append(result.allocator, try result.intern(module_name));
                    }
                }
            }
        }
    }

    return result;
}
