const input_codes = @cImport({
    @cInclude("linux/input-event-codes.h");
});

const xkb = @import("xkbcommon");
const Keysym = xkb.Keysym;
const wayland = @import("wayland");
const river = wayland.client.river;

const binding = @import("../binding.zig");

const alt: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod1);
const super: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod4);
const ctrl: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.ctrl);
const shift: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.shift);
pub const Mode = enum {
    default,
};

const XkbBinding = struct {
    mode: Mode = .default,
    keysym: u32,
    modifiers: u32,
    event: river.XkbBindingV1.Event = .pressed,
    action: binding.Action,
};

const PointerBinding = struct {
    mode: Mode = .default,
    button: u32,
    modifiers: u32,
    action: binding.Action,
    event: river.PointerBindingV1.Event = .pressed,
};


pub const xkb_bindings = [_]XkbBinding {
    .{
        .keysym = Keysym.q,
        .modifiers = .{ .mod4 = true },
        .action = .quit,
    },
    .{
        .keysym = Keysym.p,
        .modifiers = .{ .mod4 = true },
        .action = .{ .spawn = &[_][]const u8 { "wmenu-run" } },
    }
};

pub const pointer_bindings = [_]PointerBinding {
    .{
        .button = input_codes.BTN_LEFT,
        .modifiers = .{ .mod4 = true },
        .action = .pointer_move,
    },
    .{
        .button = input_codes.BTN_RIGHT,
        .modifiers = .{ .mod4 = true },
        .action = .pointer_resize
    },
};
