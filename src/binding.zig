const wayland = @import("wayland");
const river = wayland.client.river;
const wl = wayland.client.wl;

pub const XkbBinding = @import("binding/xkb_binding.zig");
pub const PointerBinding = @import("binding/pointer_binding.zig");

const config = @import("config.zig");
const layout = @import("layout.zig");
const Context = @import("context.zig");

const MoveResizeStep = union(enum) {
    horizontal: i32,
    vertical: i32,
};

pub const Arg = union(enum) {
    i: i32,
    f: f32,
    ui: u32,
    v: []const []const u8,
};

pub const Action = union(enum) {
    quit,
    close,
    spawn: struct {
        argv: []const []const u8,
    },
    spawn_shell: struct {
        cmd: []const u8,
    },
    focus_iter: struct {
        direction: wl.list.Direction,
        skip_floating: bool = false,
    },
    move: struct {
        step: MoveResizeStep,
    },
    resize: struct {
        step: MoveResizeStep,
    },
    pointer_move,
    pointer_resize,
    snap: struct {
        edges: river.WindowV1.Edges,
    },
    switch_mode: struct {
        mode: config.Mode,
    },
    toggle_fullscreen: struct {
        in_window: bool = false,
    },
    set_output_tag: struct { tag: u32 },
    set_window_tag: struct { tag: u32 },
    toggle_output_tag: struct { mask: u32 },
    toggle_window_tag: struct { mask: u32 },
    toggle_floating,
    zoom,
    switch_layout: struct { layout: layout.Type },
    custom_fn: struct {
        arg: Arg,
        func: *const fn(*const Context, *const Arg) void,
    },
};
