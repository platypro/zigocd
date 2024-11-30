const std = @import("std");
const header_gen = @import("header-gen");
const parser = header_gen.parser;
const expor = header_gen.exporter;

fn getStringArg(
    src: []const u8,
    short: u8,
    long: []const u8,
    iter: *std.process.ArgIterator,
) ?[]const u8 {
    if (src.len < 2) {
        return null;
    }
    if (src[0] == '-' and src[1] == short) {
        if (src.len == 2) {
            if (iter.next()) |output_path| {
                return output_path;
            }
        } else {
            return src[2..];
        }
    }
    if (src[0] == '-' and src[1] == '-' and std.mem.eql(u8, src[2..], long)) {
        if (src[2 + long.len] == '=' and src.len > (3 + long.len)) {
            return src[3 + long.len ..];
        } else if (src.len == (2 + long.len)) {
            if (iter.next()) |output_path| {
                return output_path;
            }
        }
    }
    return null;
}

fn do_main(allocator: std.mem.Allocator) !void {
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_dir);

    var output_dir: ?[:0]const u8 = null;
    defer if (output_dir != null) {
        allocator.free(output_dir.?);
    };
    var input_files: std.ArrayList([:0]const u8) = std.ArrayList([:0]const u8).init(allocator);
    defer {
        for (input_files.items) |file| {
            allocator.free(file);
        }
        input_files.deinit();
    }

    var args_iterator = try std.process.argsWithAllocator(allocator);
    defer args_iterator.deinit();
    _ = args_iterator.next(); // skip first
    while (args_iterator.next()) |arg| {
        if (getStringArg(arg, 'o', "output", &args_iterator)) |string| {
            if (output_dir == null) {
                output_dir = try allocator.dupeZ(u8, string);
            }
        } else {
            try input_files.append(try allocator.dupeZ(u8, arg));
        }
    }

    if (output_dir == null) {
        std.log.err("No output directory specified", .{});
        std.process.exit(1);
    }

    var dir = file: {
        if (std.fs.path.isAbsolute(output_dir.?))
            break :file try std.fs.openDirAbsolute(std.mem.span(output_dir.?.ptr), .{})
        else
            break :file try std.fs.cwd().openDir(std.mem.span(output_dir.?.ptr), .{});
    };
    defer dir.close();
    for (input_files.items) |input_file| {
        std.debug.print("Processing file {s}\n", .{input_file});

        const path_base = std.fs.path.basename(input_file);
        const sub_path = try std.fmt.allocPrint(allocator, "{s}.zig", .{path_base[0 .. std.mem.indexOf(u8, path_base, ".") orelse input_file.len]});
        defer allocator.free(sub_path);
        const file = try dir.createFile(sub_path, .{});
        const parsed_file = try parser.parse_file(allocator, input_file);
        defer parsed_file.deinit();
        const bytes = try expor.export_zig(parsed_file);
        defer allocator.free(bytes);
        try file.writeAll(bytes);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    try do_main(allocator);

    _ = gpa.detectLeaks();
}
