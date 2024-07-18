const std = @import("std");

var arr: [4]u8 = .{ 0, 5, 0, 0 };

// Symbols from linker script
extern const _data_load_begin: usize;
extern const _data_begin: usize;
extern const _data_end: usize;

extern const _bss_begin: usize;
extern const _bss_end: usize;

export fn _start() callconv(.Naked) noreturn {
    @setRuntimeSafety(false);
    const data_size = _data_end - _data_begin;
    @memcpy(
        @as([*]u8, @ptrFromInt(_data_begin))[0..data_size],
        @as([*]u8, @ptrFromInt(_data_load_begin))[0..data_size],
    );
    @memset(@as([*]u8, @ptrFromInt(_bss_begin))[0 .. _bss_end - _bss_begin], 0);
    @setRuntimeSafety(true);
    asm volatile (
        \\
        \\ret: blx r0
        \\     b ret
        :
        : [main] "{r0}" (main),
    );
}

export fn main() void {
    arr[0] = arr[1] + 5;
    while (true) {}
}
