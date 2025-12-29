const xkb = @import("xkbcommon");
const Keysym = xkb.Keysym;
const wayland = @import("wayland");
const river = wayland.client.river;

const binding = @import("binding.zig");

const alt: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod1);
const super: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod4);
const ctrl: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.ctrl);
const shift: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.shift);
const Button = struct {
    const left = 0x110;
    const right = 0x111;
    const middle = 0x112;
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
const BorderColor = struct {
    focus: u32,
    unfocus: u32,
    urgent: u32,
};

pub const Mode = enum {
    default,
    passthrough,
};

pub const border_width = 3;
pub const border_color: BorderColor = .{
    .focus = 0xA54242,
    .unfocus = 0x707880,
    .urgent = 0xff0000,
};


pub const xkb_bindings = blk: {
    const bindings = [_]XkbBinding {
        .{
            .keysym = Keysym.Escape,
            .modifiers = super,
            .action = .{ .switch_mode = .passthrough }
        },
        .{
            .mode = .passthrough,
            .keysym = Keysym.Escape,
            .modifiers = super,
            .action = .{ .switch_mode = .default }
        },

        .{
            .keysym = Keysym.q,
            .modifiers = super,
            .action = .quit,
        },
        .{
            .keysym = Keysym.c,
            .modifiers = super,
            .action = .close,
        },
        .{
            .keysym = Keysym.p,
            .modifiers = super,
            .action = .{ .spawn = &[_][]const u8 { "wmenu-run" } },
        },
        .{
            .keysym = Keysym.f,
            .modifiers = super,
            .action = .{ .toggle_fullscreen = .{ .in_window = true } },
        },
        .{
            .keysym = Keysym.f,
            .modifiers = super|shift,
            .action = .{ .toggle_fullscreen = .{} },
        },
        .{
            .keysym = Keysym.l,
            .modifiers = super|ctrl,
            .action = .{ .move = .{ .horizontal = 10 } }
        },
        .{
            .keysym = Keysym.h,
            .modifiers = super|ctrl,
            .action = .{ .move = .{ .horizontal = -10 } }
        },
        .{
            .keysym = Keysym.j,
            .modifiers = super|ctrl,
            .action = .{ .move = .{ .vertical = 10 } }
        },
        .{
            .keysym = Keysym.k,
            .modifiers = super|ctrl,
            .action = .{ .move = .{ .vertical = -10 } }
        },
        .{
            .keysym = Keysym.l,
            .modifiers = super|alt,
            .action = .{ .resize = .{ .horizontal = 10 } }
        },
        .{
            .keysym = Keysym.h,
            .modifiers = super|alt,
            .action = .{ .resize = .{ .horizontal = -10 } }
        },
        .{
            .keysym = Keysym.j,
            .modifiers = super|alt,
            .action = .{ .resize = .{ .vertical = 10 } }
        },
        .{
            .keysym = Keysym.k,
            .modifiers = super|alt,
            .action = .{ .resize = .{ .vertical = -10 } }
        },
        .{
            .keysym = Keysym.l,
            .modifiers = super|ctrl|shift,
            .action = .{ .snap = .{ .right = true } }
        },
        .{
            .keysym = Keysym.h,
            .modifiers = super|ctrl|shift,
            .action = .{ .snap = .{ .left = true } }
        },
        .{
            .keysym = Keysym.j,
            .modifiers = super|ctrl|shift,
            .action = .{ .snap = .{ .bottom = true } }
        },
        .{
            .keysym = Keysym.k,
            .modifiers = super|ctrl|shift,
            .action = .{ .snap = .{ .top = true } }
        },
        .{
            .keysym = Keysym.@"0",
            .modifiers = super,
            .action = .{ .set_output_tag = 0xffffffff }
        }
    };

    const tag_num = 9;
    var tag_binddings: [tag_num*4]XkbBinding = undefined;
    for (0..tag_num) |i| {
        tag_binddings[i*4] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = super,
            .action = .{ .set_output_tag = 1 << i },
        };
        tag_binddings[i*4+1] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = super|shift,
            .action = .{ .set_window_tag = 1 << i },
        };
        tag_binddings[i*4+2] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = super|ctrl,
            .action = .{ .toggle_output_tag = 1 << i },
        };
        tag_binddings[i*4+3] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = super|ctrl|shift,
            .action = .{ .toggle_window_tag = 1 << i },
        };
    }

    break :blk bindings ++ tag_binddings;
};

pub const pointer_bindings = [_]PointerBinding {
    .{
        .button = Button.left,
        .modifiers = super,
        .action = .pointer_move,
    },
    .{
        .button = Button.right,
        .modifiers = super,
        .action = .pointer_resize,
    },
};
