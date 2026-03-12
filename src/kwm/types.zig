const wayland = @import("wayland");
const river = wayland.client.river;

pub const Button = enum(u32) {
    none = 0,
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

pub const BarArea = enum {
    tags,
    layout,
    mode,
    title,
    status,
};

pub const LayoutMasterLocation = enum {
    left,
    right,
    top,
    bottom,
};
