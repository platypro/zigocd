const std = @import("std");

const Error = error{
    BadFileType,
};

pub fn load(path: []const u8) !@This() {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    const fileReader = file.reader();

    const elfhdr = try fileReader.readStruct(std.elf.Elf32_Ehdr);
    if (!std.mem.eql(u8, elfhdr.e_ident[0..4], &.{ 0x7f, 'E', 'L', 'F' }) or elfhdr.e_machine != .ARM) {
        return Error.BadFileType;
    }

    // file.seekTo(elfhdr.e_shoff);
    // fileReader.readStruct(comptime T: type)

    return .{};
}

pub fn close(self: @This()) void {
    _ = self;
}
