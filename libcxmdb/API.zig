const std = @import("std");
const Node = @import("Node.zig");
const cxmdb = @import("libcxmdb.zig");

pub const apis = &.{
    @import("API/SWD.zig"),
    @import("API/USB.zig"),
};

const AnyError = blk: {
    var errors: type = cxmdb.Error;
    for (apis) |api| {
        const to_add = @typeInfo(@typeInfo(@TypeOf(api.init)).@"fn".return_type.?).error_union.error_set;
        errors = errors || to_add;
    }
    break :blk errors;
};

const InitType = *const fn (*@This()) AnyError!void;
const DeinitType = *const fn (*@This()) void;

const InitDeinit = struct {
    init: []const InitType,
    deinit: []const DeinitType,
};

allocator: std.mem.Allocator,
type: api_enum,
user_data: ?api_union,
parent_node: *Node,
vtable: api_vtable_union,

pub fn getParentContext(self: @This(), comptime typ: Node.node_enum) !*Node.nodes[@intFromEnum(typ)] {
    return self.parent_node.getContext(typ);
}

pub fn getContext(self: @This(), comptime typ: api_enum) !*apis[@intFromEnum(typ) -| 1] {
    if (self.user_data == null) return cxmdb.Error.NoUserData;
    return @field(self.user_data.?, @tagName(typ));
}

pub fn getVtable(self: @This(), comptime typ: api_enum) *const apis[@intFromEnum(typ) -| 1].vtable {
    return &@field(self.vtable, @tagName(typ));
}

pub const api_enum = blk: {
    var result = std.builtin.Type{
        .@"enum" = .{
            .tag_type = u32,
            .fields = &.{},
            .decls = &.{},
            .is_exhaustive = true,
        },
    };

    // Add "Null Field"
    result.@"enum".fields = result.@"enum".fields ++ [_]std.builtin.Type.EnumField{.{
        .name = "null",
        .value = 0,
    }};

    for (apis, 1..) |api, i| {
        result.@"enum".fields = result.@"enum".fields ++ [_]std.builtin.Type.EnumField{.{
            .name = @tagName(api.name),
            .value = i,
        }};
    }

    break :blk @Type(result);
};

pub const api_vtable_union = blk: {
    var result = std.builtin.Type{
        .@"union" = .{
            .layout = .auto,
            .tag_type = api_enum,
            .fields = &.{},
            .decls = &.{},
        },
    };

    // Add null vtable
    result.@"union".fields = result.@"union".fields ++ [_]std.builtin.Type.UnionField{.{
        .name = "null",
        .type = void,
        .alignment = @alignOf(void),
    }};

    for (apis) |api| {
        result.@"union".fields = result.@"union".fields ++ [_]std.builtin.Type.UnionField{.{
            .name = @tagName(api.name),
            .type = api.vtable,
            .alignment = @alignOf(api.vtable),
        }};
    }

    break :blk @Type(result);
};

pub const api_union = blk: {
    var result = std.builtin.Type{
        .@"union" = .{
            .layout = .auto,
            .tag_type = api_enum,
            .fields = &.{},
            .decls = &.{},
        },
    };

    // Add null api
    result.@"union".fields = result.@"union".fields ++ [_]std.builtin.Type.UnionField{.{
        .name = "null",
        .type = void,
        .alignment = @alignOf(void),
    }};

    for (apis) |api| {
        const apiptr = @Type(std.builtin.Type{
            .pointer = .{
                .size = .One,
                .is_const = false,
                .is_volatile = false,
                .alignment = @alignOf(api),
                .address_space = .generic,
                .child = api,
                .is_allowzero = false,
                .sentinel = null,
            },
        });

        result.@"union".fields = result.@"union".fields ++ [_]std.builtin.Type.UnionField{.{
            .name = @tagName(api.name),
            .type = apiptr,
            .alignment = @alignOf(apiptr),
        }};
    }

    break :blk @Type(result);
};

pub const api_init_deinit = blk: {
    var result: InitDeinit = .{ .init = &.{}, .deinit = &.{} };
    for (apis) |api| {
        result.init = result.init ++ [_]InitType{&api.init};
        result.deinit = result.deinit ++ [_]DeinitType{&api.deinit};
    }
    break :blk result;
};

pub fn getClass(comptime typ: api_enum) type {
    return apis[@intFromEnum(typ) - 1];
}
