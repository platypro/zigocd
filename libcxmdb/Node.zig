const std = @import("std");
const API = @import("API.zig");
const cxmdb = @import("libcxmdb.zig");

pub const nodes = .{
    @import("Node/Host.zig"),
    @import("Node/JLink.zig"),
    @import("Node/SAMD51.zig"),
};

const ApiMap = std.AutoArrayHashMapUnmanaged(API.api_enum, *API);

const AnyError = blk: {
    var errors: type = cxmdb.Error;
    for (nodes) |node| {
        const to_add = @typeInfo(@typeInfo(@TypeOf(node.init)).@"fn".return_type.?).error_union.error_set;
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

const Error = error{
    NoTransport,
};

allocator: std.mem.Allocator,
id: node_enum,
user_data: ?node_union,
transport: ?*API,
apis: ApiMap,

pub fn cast_handle(self: @This(), comptime id: node_enum) nodes[id] {
    return @alignCast(@ptrCast(self.handle));
}

pub const node_init_deinit = blk: {
    var result: InitDeinit = .{ .init = &.{}, .deinit = &.{} };
    for (nodes) |node| {
        result.init = result.init ++ [_]InitType{node.init};
        result.deinit = result.deinit ++ [_]DeinitType{node.deinit};
    }
    break :blk result;
};

pub const node_enum = blk: {
    var result = std.builtin.Type{
        .@"enum" = .{
            .tag_type = u32,
            .fields = &.{},
            .decls = &.{},
            .is_exhaustive = true,
        },
    };
    for (nodes, 0..) |node, i| {
        result.@"enum".fields = result.@"enum".fields ++ [_]std.builtin.Type.EnumField{.{
            .name = @tagName(node.name),
            .value = i,
        }};
    }
    break :blk @Type(result);
};

pub const node_union = blk: {
    var result = std.builtin.Type{
        .@"union" = .{
            .layout = .auto,
            .tag_type = node_enum,
            .fields = &.{},
            .decls = &.{},
        },
    };

    for (nodes) |node| {
        const nodeptr = @Type(std.builtin.Type{
            .pointer = .{
                .size = .One,
                .is_const = false,
                .is_volatile = false,
                .alignment = @alignOf(node),
                .address_space = .generic,
                .child = node,
                .is_allowzero = false,
                .sentinel = null,
            },
        });

        result.@"union".fields = result.@"union".fields ++ [_]std.builtin.Type.UnionField{.{
            .name = @tagName(node.name),
            .type = nodeptr,
            .alignment = @alignOf(nodeptr),
        }};
    }

    break :blk @Type(result);
};

pub fn init(self: *@This(), allocator: std.mem.Allocator, node_type: node_enum) !void {
    self.user_data = null;
    self.allocator = allocator;
    self.apis = ApiMap{};
    self.transport = null;
    self.id = node_type;
    try node_init_deinit.init[@intFromEnum(node_type)](self);
}

pub fn deinit(self: *@This()) void {
    node_init_deinit.deinit[@intFromEnum(self.id)](self);
    for (self.apis.values()) |api| {
        self.allocator.destroy(api);
    }
    self.apis.deinit(self.allocator);
}

pub fn register_api(self: *@This(), comptime typ: API.api_enum, vtable: API.api_vtable_union) !void {
    const api = try self.allocator.create(API);
    api.allocator = self.allocator;
    api.parent_node = self;
    api.user_data = null;
    api.vtable = vtable;
    api.type = typ;

    try API.api_init_deinit.init[@intFromEnum(typ) -| 1](api);
    try self.apis.put(self.allocator, typ, api);
}

pub fn getApi(self: @This(), comptime api: API.api_enum) !*API {
    const result = self.apis.get(api);
    if (result == null) {
        return cxmdb.Error.NoApi;
    }
    return result.?;
}

pub fn getContext(self: @This(), comptime typ: node_enum) !*nodes[@intFromEnum(typ)] {
    if (self.user_data == null) return cxmdb.Error.NoUserData;
    return @field(self.user_data.?, @tagName(typ));
}

pub fn getClass(comptime typ: node_enum) type {
    return nodes[@intFromEnum(typ)];
}

pub fn getTransportVTable(self: @This()) API.api_vtable_union {
    const api_null_union = API.api_vtable_union{ .null = {} };
    if (self.transport == null) {
        return api_null_union;
    }
    return self.transport.?.vtable;
}
