const build_options = @import("build_options");

const wayland = @import("wayland");
const river = wayland.client.river;

const layout = @import("layout.zig");
const Context = @import("context.zig");

const KeyboardState = enum {
    enabled,
    disabled,
};

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

pub const KeyboardNumlockState = KeyboardState;
pub const KeyboardCapslockState = KeyboardState;
pub const KeyboardLayout = union(enum) {
    index: u32,
    name: [*:0]const u8,
};
pub const Keymap = struct {
    file: []const u8,
    format: river.XkbConfigV1.KeymapFormat,
};

pub const State = struct {
    layout: ?layout.Type,
};
