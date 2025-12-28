const wayland = @import("wayland");
const river = wayland.client.river;

pub const XkbBinding = @import("binding/xkb_binding.zig");
pub const PointerBinding = @import("binding/pointer_binding.zig");

const config = @import("config.zig");

const MoveResizeStep = union(enum) {
    horizontal: i32,
    vertical: i32,
};

pub const Action = union(enum) {
    quit,
    close,
    spawn: []const []const u8,
    spawn_shell: []const u8,
    move: MoveResizeStep,
    resize: MoveResizeStep,
    pointer_move,
    pointer_resize,
    snap: river.WindowV1.Edges,
    switch_mode: config.seat.Mode,
    toggle_fullscreen: struct {
        in_window: bool = false,
    },
    set_output_tag: u32,
    set_window_tag: u32,
    toggle_output_tag: u32,
    toggle_window_tag: u32,
};
