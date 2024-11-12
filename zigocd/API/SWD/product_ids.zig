const std = @import("std");
const Renderer = @import("renderer");

// These product IDs were taken from openocd from file src/target/arm_adi_v5.c

pub const CoresightId = struct {
    manufacturer: u12,
    product: u12,
    name: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const input_file_name = args[1];
    const output_file_name = args[2];

    const input_file = try std.fs.openFileAbsolute(input_file_name, .{ .mode = .read_only });
    defer input_file.close();
    std.debug.print("File path: {s}", .{output_file_name});
    const output_file = try std.fs.createFileAbsolute(output_file_name, .{});
    defer output_file.close();
    var buf: [50]u8 = undefined;

    var renderer = try Renderer.init(allocator, 0);
    // _ = renderer

    try renderer.src.appendSlice(renderer.allocator,
        \\ pub const CoresightId = struct {
        \\     manufacturer: u12,
        \\     product: u12,
        \\     name: []const u8,
        \\ };
    );

    try renderer.push(&.{ .keyword_pub, .keyword_const });
    try renderer.push_identifier("ids", .{});
    try renderer.push(&.{ .equal, .ampersand, .l_bracket });
    try renderer.push_identifier("_", .{});
    try renderer.push(&.{.r_bracket});
    try renderer.push_identifier("CoresightId", .{});
    try renderer.push(&.{.l_brace});
    while (input_file.reader().readUntilDelimiter(&buf, '\n') catch null) |entry| {
        // var element: CoresightId = undefined;
        var field_iter = std.mem.splitAny(u8, entry, ",\n");

        try renderer.push(&.{ .period, .l_brace });

        const manufacturer = std.fmt.parseInt(u16, field_iter.next().?, 0) catch break;
        const product = std.fmt.parseInt(u16, field_iter.next().?, 0) catch break;
        const name = field_iter.next() orelse break;
        // result = result ++ [_]CoresightId{element};
        try renderer.push(&.{.period});
        try renderer.push_identifier("manufacturer", &.{});
        try renderer.push(&.{.equal});
        try renderer.push_int(manufacturer);
        try renderer.push(&.{.comma});
        try renderer.push(&.{.period});
        try renderer.push_identifier("product", &.{});
        try renderer.push(&.{.equal});
        try renderer.push_int(product);
        try renderer.push(&.{.comma});
        try renderer.push(&.{.period});
        try renderer.push_identifier("name", &.{});
        try renderer.push(&.{.equal});
        try renderer.push_string_literal(name);
        try renderer.push(&.{.comma});

        try renderer.push(&.{ .r_brace, .comma });
    }

    try renderer.push(&.{ .r_brace, .semicolon });
    const src = try renderer.render();
    try output_file.writeAll(src);
    renderer.allocator.free(src);
}
