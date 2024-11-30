const source = @import("source.zig");
const vector_table = @import("vector_table.zig");

extern const _bss_start: c_uint;
extern const _bss_end: c_uint;

extern const _data_start: c_uint;
extern const _data_end: c_uint;

extern const _data_load_start: c_uint;
extern const _stack_start: c_uint;

export fn _start() callconv(.Naked) noreturn {
    const _bss_size = _bss_end - _bss_start;
    const _data_size = _data_end - _data_start;
    @setRuntimeSafety(false);
    @memcpy(
        @as([*]u8, @ptrFromInt(_data_start))[0.._data_size],
        @as([*]const u8, @ptrFromInt(_data_load_start))[0.._data_size],
    );
    @memset(
        @as([*]u8, @ptrFromInt(_bss_start))[0.._bss_size],
        0,
    );

    asm volatile (
        \\ mov sp, %[_stack_start]
        \\ blx %[main:P]
        :
        : [main] "{r1}" (&_main),
          [_stack_start] "{r2}" (&_stack_start),
    );

    while (true) {
        continue;
    }
}

export fn _main() callconv(.C) void {
    source.main();
}
