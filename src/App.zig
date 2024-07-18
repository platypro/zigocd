const std = @import("std");
const mach = @import("mach");

pub const name = .app;
pub const Mod = mach.Mod(@This());

pub const systems = .{
    .init = .{ .handler = init },
    .tick = .{ .handler = tick },
    .deinit = .{ .handler = deinit },
    .after_init = .{ .handler = after_init },
};

pub fn init(mod: *Mod, core: *mach.Core.Mod) void {
    core.schedule(.init);
    mod.schedule(.after_init);
}

pub fn after_init(mod: *Mod) void {
    _ = mod;
}

pub fn tick(mod: *Mod, core: *mach.Core.Mod) void {
    core.schedule(.present_frame);
    _ = mod;
}

pub fn deinit(mod: *Mod, core: *mach.Core.Mod) void {
    core.schedule(.deinit);
    _ = mod;
}
