pub const XkbBinding = @import("binding/xkb_binding.zig");
pub const PointerBinding = @import("binding/pointer_binding.zig");

const config = @import("config.zig");

const Direction = enum {};

pub const Action = union(enum) {
    quit,
    spawn: []const []const u8,
    spawn_shell: []const u8,
    move,
    resize,
    pointer_move,
    pointer_resize,
    switch_mode: config.seat.Mode,
};
