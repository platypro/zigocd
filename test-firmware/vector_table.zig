const std = @import("std");
const builtin = @import("builtin");

pub const VectorCallConv = std.builtin.CallingConvention{ .arm_interrupt = .{ .type = .irq } };
const Vector = *const fn () callconv(VectorCallConv) void;

extern fn _start() callconv(.Naked) noreturn;

fn default_handler() callconv(VectorCallConv) void {
    while (true) {
        @breakpoint();
    }
}
comptime {
    @export(&default_handler, .{ .linkage = .weak, .name = "NonMaskableInt_Handler", .section = ".text", .visibility = .default });
}

extern fn NonMaskableInt_Handler() callconv(VectorCallConv) void;

// Stack pointer included in linker script itself
const VectorTable = extern struct {
    pfnReset_Handler: Vector = _start,
    pfnNonMaskableInt_Handler: Vector = NonMaskableInt_Handler,
    pfnHardFault_Handler: Vector = default_handler,
    pfnMemManagement_Handler: Vector = default_handler,
    pfnBusFault_Handler: Vector = default_handler,
    pfnUsageFault_Handler: Vector = default_handler,
    pvReservedM9: Vector = default_handler,
    pvReservedM8: Vector = default_handler,
    pvReservedM7: Vector = default_handler,
    pvReservedM6: Vector = default_handler,
    pfnSVCall_Handler: Vector = default_handler,
    pfnDebugMonitor_Handler: Vector = default_handler,
    pvReservedM3: Vector = default_handler,
    pfnPendSV_Handler: Vector = default_handler,
    pfnSysTick_Handler: Vector = default_handler,
};

export const vector_table linksection(".vector_table") = VectorTable{};
