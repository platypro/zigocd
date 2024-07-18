const std = @import("std");

const Error = error{
    BadFileType,
};

fn load(path: []const u8) @This() {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    const fileReader = file.reader();

    const elfhdr = try fileReader.readStruct(std.elf.Elf32_Ehdr);
    if (!std.mem.eql(elfhdr.e_ident[0..4], .{ 0x7f, 'E', 'L', 'F', 0x01 }) or elfhdr.e_machine != .ARM) {
        return Error.BadFileType;
    }
}

// std.fs.selfExeDirPathAlloc();

// std.elf.Header.
