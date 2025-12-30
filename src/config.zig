const std = @import("std");

const xkb = @import("xkbcommon");
const Keysym = xkb.Keysym;
const wayland = @import("wayland");
const river = wayland.client.river;

const binding = @import("binding.zig");
const Context = @import("context.zig");
const Rule = @import("rule.zig");

const Alt: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod1);
const Super: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod4);
const Ctrl: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.ctrl);
const Shift: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.shift);
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

pub var border_width: i32 = 3;
pub const border_color: BorderColor = .{
    .focus = 0xffc777,
    .unfocus = 0x828bb8,
    .urgent = 0xff0000,
};


pub var layout: struct {
    tile: @import("layout/tile.zig"),
    monocle: @import("layout/monocle.zig"),
    scroller: @import("layout/scroller.zig"),
} = .{
    .tile = .{
        .nmaster = 1,
        .mfact = 0.55,
        .gap = 10,
    },
    .monocle = .{
        .gap = 10,
    },
    .scroller = .{
        .mfact = 0.6,
        .gap = 10,
    }
};

fn modify_nmaster(context: *const Context, arg: *const binding.Arg) void {
    std.debug.assert(arg.* == .i);

    if (context.current_output) |output| {
        switch (output.current_layout()) {
            .tile => layout.tile.nmaster = @max(1, layout.tile.nmaster+arg.i),
            else => {}
        }
    }
}


fn modify_mfact(context: *const Context, arg: *const binding.Arg) void {
    std.debug.assert(arg.* == .f);

    if (context.current_output) |output| {
        switch (output.current_layout()) {
            .tile => layout.tile.mfact = @min(1, @max(0, layout.tile.mfact+arg.f)),
            .scroller => layout.scroller.mfact = @min(1, @max(0, layout.scroller.mfact+arg.f)),
            else => {},
        }
    }
}


fn modify_gap(context: *const Context, arg: *const binding.Arg) void {
    std.debug.assert(arg.* == .i);

    if (context.current_output) |output| {
        switch (output.current_layout()) {
            .tile => layout.tile.gap = @max(0, layout.tile.gap+arg.i),
            .monocle => layout.monocle.gap = @max(0, layout.monocle.gap+arg.i),
            .scroller => layout.scroller.gap = @max(0, layout.scroller.gap+arg.i),
            .float => {},
        }
    }
}


pub const xkb_bindings = blk: {
    const bindings = [_]XkbBinding {
        .{
            .keysym = Keysym.Escape,
            .modifiers = Super|Shift,
            .action = .{ .switch_mode = .{ .mode = .passthrough } }
        },
        .{
            .mode = .passthrough,
            .keysym = Keysym.Escape,
            .modifiers = Super,
            .action = .{ .switch_mode = .{ .mode = .default } }
        },

        .{
            .keysym = Keysym.q,
            .modifiers = Super|Shift,
            .action = .quit,
        },
        .{
            .keysym = Keysym.c,
            .modifiers = Super|Shift,
            .action = .close,
        },
        .{
            .keysym = Keysym.Return,
            .modifiers = Super,
            .action = .zoom,
        },
        .{
            .keysym = Keysym.l,
            .modifiers = Super,
            .action = .{ .custom_fn = .{ .func = &modify_mfact, .arg = .{ .f = 0.01 } } },
        },
        .{
            .keysym = Keysym.h,
            .modifiers = Super,
            .action = .{ .custom_fn = .{ .func = &modify_mfact, .arg = .{ .f = -0.01 } } },
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super,
            .action = .{ .focus_iter = .{ .direction = .forward, .skip_floating = true, } },
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super,
            .action = .{ .focus_iter = .{ .direction = .reverse, .skip_floating = true } },
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super|Alt,
            .action = .{ .focus_iter = .{ .direction = .forward } },
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super|Alt,
            .action = .{ .focus_iter = .{ .direction = .reverse } },
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super|Shift,
            .action = .{ .swap = .{ .direction = .forward } },
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super|Shift,
            .action = .{ .swap = .{ .direction = .reverse } },
        },
        .{
            .keysym = Keysym.period,
            .modifiers = Super,
            .action = .{ .focus_output_iter = .{ .direction = .forward } },
        },
        .{
            .keysym = Keysym.comma,
            .modifiers = Super,
            .action = .{ .focus_output_iter = .{ .direction = .reverse } },
        },
        .{
            .keysym = Keysym.f,
            .modifiers = Super,
            .action = .{ .toggle_fullscreen = .{ .in_window = true } },
        },
        .{
            .keysym = Keysym.f,
            .modifiers = Super|Shift,
            .action = .{ .toggle_fullscreen = .{} },
        },
        .{
            .keysym = Keysym.f,
            .modifiers = Super|Ctrl,
            .action = .toggle_floating,
        },
        .{
            .keysym = Keysym.f,
            .modifiers = Super|Ctrl|Alt,
            .action = .{ .switch_layout = .{ .layout = .float } },
        },
        .{
            .keysym = Keysym.t,
            .modifiers = Super,
            .action = .{ .switch_layout = .{ .layout = .tile } },
        },
        .{
            .keysym = Keysym.m,
            .modifiers = Super,
            .action = .{ .switch_layout = .{ .layout = .monocle } },
        },
        .{
            .keysym = Keysym.s,
            .modifiers = Super,
            .action = .{ .switch_layout = .{ .layout = .scroller } },
        },
        .{
            .keysym = Keysym.l,
            .modifiers = Super|Ctrl,
            .action = .{ .move = .{ .step = .{ .horizontal = 10 } } }
        },
        .{
            .keysym = Keysym.h,
            .modifiers = Super|Ctrl,
            .action = .{ .move = .{ .step = .{ .horizontal = -10 } } }
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super|Ctrl,
            .action = .{ .move = .{ .step = .{ .vertical = 10 } } }
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super|Ctrl,
            .action = .{ .move = .{ .step = .{ .vertical = -10 } } }
        },
        .{
            .keysym = Keysym.l,
            .modifiers = Super|Alt,
            .action = .{ .resize = .{ .step = .{ .horizontal = 10 } } }
        },
        .{
            .keysym = Keysym.h,
            .modifiers = Super|Alt,
            .action = .{ .resize = .{ .step = .{ .horizontal = -10 } } }
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super|Alt,
            .action = .{ .resize = .{ .step = .{ .vertical = 10 } } }
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super|Alt,
            .action = .{ .resize = .{ .step = .{ .vertical = -10 } } }
        },
        .{
            .keysym = Keysym.l,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .snap = .{ .edges = .{ .right = true } } }
        },
        .{
            .keysym = Keysym.h,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .snap = .{ .edges = .{ .left = true } } }
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .snap = .{ .edges = .{ .bottom = true } } }
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .snap = .{ .edges = .{ .top = true } } }
        },
        .{
            .keysym = Keysym.@"0",
            .modifiers = Super,
            .action = .{ .set_output_tag = .{ .tag = 0xffffffff } }
        },
        .{
            .keysym = Keysym.p,
            .modifiers = Super,
            .action = .{ .spawn = .{ .argv = &[_][]const u8 { "wmenu-run" } } },
        },
        .{
            .keysym = Keysym.Return,
            .modifiers = Super|Shift,
            .action = .{ .spawn = .{ .argv = &[_][]const u8 { "foot" } } },
        },
    };

    const tag_num = 9;
    var tag_binddings: [tag_num*4]XkbBinding = undefined;
    for (0..tag_num) |i| {
        tag_binddings[i*4] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = Super,
            .action = .{ .set_output_tag = .{ .tag = 1 << i } },
        };
        tag_binddings[i*4+1] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = Super|Shift,
            .action = .{ .set_window_tag = .{ .tag = 1 << i } },
        };
        tag_binddings[i*4+2] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = Super|Ctrl,
            .action = .{ .toggle_output_tag = .{ .mask = 1 << i } },
        };
        tag_binddings[i*4+3] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .toggle_window_tag = .{ .mask = 1 << i } },
        };
    }

    break :blk bindings ++ tag_binddings;
};

pub const pointer_bindings = [_]PointerBinding {
    .{
        .button = Button.left,
        .modifiers = Super,
        .action = .pointer_move,
    },
    .{
        .button = Button.right,
        .modifiers = Super,
        .action = .pointer_resize,
    },
};


pub const rules = [_]Rule {
    //  support regex by: https://github.com/mnemnion/mvzr
    // .{
    //     // match part
    //     .app_id = .{ .str = "pattern" } or .app_id = .compile("regex pattern"),
    //     .title = .{ .str = "pattern" } or .title = .compile("regex pattern"),
    //
    //     // apply part
    //     .tag = 1,
    //     .floating = true,
    //     .decoration = .csd or .ssd
    // },
    .{ .app_id = .{ .str = "chromium" }, .tag = 1 << 1 },
    .{ .app_id = .{ .str = "QQ" }, .tag = 1 << 2, .floating = true },
    .{ .app_id = .{ .str = "wemeetapp" }, .tag = 1 << 2, .floating = true },
    .{ .app_id = .{ .str = "wechat" }, .tag = 1 << 2, .floating = true },
    .{ .app_id = .compile(".*微信.*"), .tag = 1 << 2, .floating = true },
    .{ .app_id = .{ .str = "virt-manager" }, .floating = true },
    .{ .app_id = .{ .str = "Zotero" }, .floating = true },
    .{ .app_id = .{ .str = "stalonetray" }, .floating = true },
    .{ .app_id = .{ .str = "lazarus" }, .floating = true },
    .{ .app_id = .{ .str = "ONLYOFFICE" }, .floating = true },
};
