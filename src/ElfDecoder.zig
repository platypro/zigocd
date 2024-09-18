const std = @import("std");

allocator: std.mem.Allocator,
loadable_sections: LoadableSectionList,
load_maps: LoadMapList,
string_tables: StringTableList,

const Error = error{
    BadFileType,
};

/// A loadable section represents a chunk of memory in the virtual address space
/// which is seen by zigocd and not the target cpu.
const LoadableSection = struct {
    start_addr: usize,
    end_addr: usize,
    buf: []u8,
    name: []u8,

    // These fields are for holding information about loading buf and name fields
    name_id: usize,
    buf_file_addr: usize, // Store file addr here for second pass
};
const LoadableSectionList = std.ArrayList(LoadableSection);

/// A struct which maps ranges virtual address ranges in zigocd with physical
/// addresses on the target device.
const LoadMap = struct {
    /// Virtual (zigocd) address
    vma: usize,
    /// Physical (Target) address
    lma: usize,
    /// Size of section
    size: usize,
};
const LoadMapList = std.ArrayList(LoadMap);

/// A string table
const StringTable = struct {
    strings: []u8,

    // Temporary fields
    buf_file_addr: usize,
    total_length: usize,
};

/// A string table is associated with the section it appears in
const StringTableList = std.AutoArrayHashMap(usize, StringTable);

fn getString(self: @This(), section: usize, index: usize) []u8 {
    const table = self.string_tables.get(section).?;
    return std.mem.sliceTo(table.strings[index..table.strings.len], 0);
}

pub fn load(allocator: std.mem.Allocator, path: []const u8) !@This() {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    var self = @This(){
        .allocator = allocator,
        .loadable_sections = LoadableSectionList.init(allocator),
        .load_maps = LoadMapList.init(allocator),
        .string_tables = StringTableList.init(allocator),
    };
    const fileReader = file.reader();

    const elfhdr = try fileReader.readStruct(std.elf.Elf32_Ehdr);
    if (!std.mem.eql(u8, elfhdr.e_ident[0..4], &.{ 0x7f, 'E', 'L', 'F' }) or elfhdr.e_machine != .ARM) {
        return Error.BadFileType;
    }

    // Load sections
    try file.seekTo(elfhdr.e_shoff);
    for (0..elfhdr.e_shnum) |i| {
        const section_header = try fileReader.readStruct(std.elf.Elf32_Shdr);
        // LoadableSection
        if (section_header.sh_type != std.elf.SHT_NOBITS and (section_header.sh_flags & std.elf.SHF_ALLOC) > 0) {
            var loadable_section = try self.loadable_sections.addOne();
            loadable_section.start_addr = section_header.sh_addr;
            loadable_section.end_addr = section_header.sh_addr + section_header.sh_size;
            loadable_section.buf = try self.allocator.alloc(u8, section_header.sh_entsize);
            loadable_section.buf_file_addr = section_header.sh_offset;
            loadable_section.name_id = section_header.sh_name;
        }

        // String Table
        if (section_header.sh_type == std.elf.SHT_STRTAB) {
            const string_table = StringTable{
                .buf_file_addr = section_header.sh_offset,
                .total_length = section_header.sh_size,
                .strings = try self.allocator.alloc(u8, section_header.sh_size),
            };
            try self.string_tables.put(i, string_table);
        }
    }

    // Read string tables
    for (self.string_tables.values()) |*string_table| {
        try file.seekTo(string_table.buf_file_addr);
        _ = try fileReader.read(string_table.strings);
    }

    // Read loadable sections
    for (self.loadable_sections.items) |*item| {
        try file.seekTo(item.buf_file_addr);
        _ = try fileReader.read(item.buf);

        // We have the name now (in shstrtab), so link it up
        item.name = self.getString(elfhdr.e_shstrndx, item.name_id);
    }

    // Load program headers
    try file.seekTo(elfhdr.e_phoff);
    for (0..elfhdr.e_phnum) |_| {
        const program_header = try fileReader.readStruct(std.elf.Elf32_Phdr);
        if (program_header.p_type == std.elf.PT_LOAD) {
            var load_map = try self.load_maps.addOne();
            load_map.lma = program_header.p_paddr;
            load_map.vma = program_header.p_vaddr;
            load_map.size = program_header.p_filesz;
        }
    }

    return self;
}

pub fn close(self: *@This()) void {
    for (self.loadable_sections.items) |section| {
        self.allocator.free(section.buf);
    }
    self.loadable_sections.deinit();

    for (self.string_tables.values()) |string_table| {
        self.allocator.free(string_table.strings);
    }
    self.string_tables.deinit();

    self.load_maps.deinit();
}
