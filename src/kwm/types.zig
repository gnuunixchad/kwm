const build_options = @import("build_options");

const wayland = @import("wayland");
const river = wayland.client.river;

const config = @import("config");

const layout = @import("layout.zig");

pub const Button = enum(u32) {
    left = 0x110,
    right = 0x111,
    middle = 0x112,
};

pub const Direction = enum {
    forward,
    reverse,
};

pub const PlacePosition = union(enum) {
    top,
    bottom,
    above: *river.NodeV1,
    below: *river.NodeV1,
};


const Window = struct {
    title: ?[]const u8,
    app_id: ?[]const u8,
};
pub const State = struct {
    mode: config.Mode,
    layout: ?layout.Type,
    focused_window: ?Window,
    window_below_pointer: ?Window,
};
