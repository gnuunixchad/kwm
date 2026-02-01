////////////////////////////////////////////////////////
// Configure irrelevant part
////////////////////////////////////////////////////////
const std = @import("std");
const fmt = std.fmt;

const xkb = @import("xkbcommon");
const Keysym = xkb.Keysym;
const wayland = @import("wayland");
const river = wayland.client.river;

const kwm = @import("kwm");
const rule = @import("src/config/rule.zig");

pub const WindowRule = rule.Window;
pub const InputDeviceRule = rule.InputDevice;
pub const LibinputDeviceRule = rule.LibinputDevice;
pub const XkbKeyboardRule = rule.XkbKeyboard;

const Alt: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod1);
const Super: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod4);
const Ctrl: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.ctrl);
const Shift: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.shift);
const Button = kwm.Button;
const XcursorTheme = struct {
    name: []const u8,
    size: u32,
};
const BarColor = struct {
    fg: u32,
    bg: u32,
};
const BarConfig = struct {
    show_default: bool,
    position: enum {
        top,
        bottom,
    },
    font: []const u8,
    color: struct {
        normal: BarColor,
        select: BarColor,
    },
    status: union(enum) {
        text: []const u8,
        stdin,
        fifo: []const u8,
    },
    click: std.EnumMap(enum { tag, layout, mode, title, status }, std.EnumMap(Button, kwm.BindingAction)),
};
const XkbBinding = struct {
    mode: Mode = .default,
    keysym: u32,
    modifiers: u32,
    event: kwm.XkbBindingEvent = .pressed,
    action: kwm.BindingAction,
};
const PointerBinding = struct {
    mode: Mode = .default,
    button: Button,
    modifiers: u32,
    action: kwm.BindingAction,
    event: kwm.PointerBindingEvent = .pressed,
};
const BorderColor = struct {
    focus: u32,
    unfocus: u32,
    urgent: u32,
};


////////////////////////////////////////////////////////
// Configure part
////////////////////////////////////////////////////////

const term_cmd = "foot";

pub const env = [_] struct { []const u8, []const u8 } {
    // .{ "key", "value" },
};

pub const working_directory: union(enum) {
    none,
    home,
    custom: []const u8,
} = .home;

pub const startup_cmds = [_][]const []const u8 {
    // &[_][]const u8 { "swaybg", "-i", "/path/to/wallpaper" },
};

pub const xcursor_theme: ?XcursorTheme = null;

pub const repeat_rate = 50;
pub const repeat_delay = 300;

pub const sloppy_focus = false;

pub const bar: BarConfig = .{
    .show_default = true,
    .position = .top,
    .font = "monospace:size=10",
    .color = .{
        .normal = .{
            .fg = 0x828bb8ff,
            .bg = 0x1b1d2bd0,
        },
        .select = .{
            .fg = 0x444a73ff,
            .bg = 0xc8d3f5d0,
        },
    },
    .status = .{ .text = "kwm" }, // .stdin or .{ .fifo = "fifo file path" }
    // bar clicked callback
    // each part support left/right/middle
    .click = .init(.{
        .tag = .init(.{
            // could use undefined there because it will be replace with the tag clicked
            .left = .{ .set_output_tag = undefined },
            .right = .{ .toggle_output_tag = undefined },
            .middle = .{ .toggle_window_tag = undefined },
        }),
        .layout = .init(.{
            .left = .switch_to_previous_layout,
        }),
        .mode = .init(.{
            .left = .{ .switch_mode = .{ .mode = .default } },
        }),
        .title = .init(.{
            .left = .zoom,
        }),
        .status = .init(.{
            .middle = .{ .spawn = .{ .argv = &[_][]const u8 { term_cmd } } }
        })
    }),
};

pub var auto_swallow = true;

pub const default_window_decoration: kwm.WindowDecoration = .ssd;

pub var border_width: i32 = 5;
pub const border_color: BorderColor = .{
    .focus = 0xffc777ff,
    .unfocus = 0x828bb8ff,
    .urgent = 0xff0000ff,
};


pub const default_layout: kwm.layout.Type = .tile;
pub var tile: kwm.layout.tile = .{
    .nmaster = 1,
    .mfact = 0.55,
    .inner_gap = 12,
    .outer_gap = 9,
    .master_location = .left,
};
pub var grid: kwm.layout.grid = .{
    .outer_gap = 9,
    .inner_gap = 12,
    .direction = .horizontal,
};
pub var monocle: kwm.layout.monocle = .{
    .gap = 9,
};
pub var scroller: kwm.layout.scroller = .{
    .mfact = 0.5,
    .inner_gap = 16,
    .outer_gap = 9,
    .master_location = .center,
};
pub fn layout_tag(layout: kwm.layout.Type) []const u8 {
    return switch (layout) {
        .tile => switch (tile.master_location) {
            .left => "[]=",
            .right => "=[]",
            .top => "[^]",
            .bottom => "[_]",
        },
        .grid => switch (grid.direction) {
            .horizontal => "|+|",
            .vertical => "|||",
        },
        .monocle => "[=]",
        .scroller => switch (scroller.master_location) {
            .left =>  "[<-]",
            .center => "[==]",
        },
        .float => "><>",
    };
}


//////////////////////////////////////////////////////////
// custom function for `custom_fn` binding action
// below are some useful example
// it could use to modify some variable define above or
// dynamicly return a binding action
// You could define other functions as you wish
//////////////////////////////////////////////////////////

fn modify_nmaster(state: *const kwm.State, arg: *const kwm.BindingArg) ?kwm.BindingAction {
    std.debug.assert(arg.* == .i);

    if (state.layout == .tile) {
        tile.nmaster = @max(1, tile.nmaster+arg.i);
    }

    return null;
}


fn modify_mfact(state: *const kwm.State, arg: *const kwm.BindingArg) ?kwm.BindingAction {
    std.debug.assert(arg.* == .f);

    if (state.layout) |layout_t| {
        switch (layout_t) {
            .tile => tile.mfact = @min(1, @max(0, tile.mfact+arg.f)),
            .scroller => return .{ .modify_scroller_mfact = .{ .step = arg.f } },
            else => {},
        }
    }

    return null;
}


fn modify_gap(state: *const kwm.State, arg: *const kwm.BindingArg) ?kwm.BindingAction {
    std.debug.assert(arg.* == .i);

    if (state.layout) |layout_t| {
        switch (layout_t) {
            .tile => tile.inner_gap = @max(border_width*2, tile.inner_gap+arg.i),
            .grid => grid.inner_gap = @max(border_width*2, grid.inner_gap+arg.i),
            .monocle => monocle.gap = @max(border_width*2, monocle.gap+arg.i),
            .scroller => scroller.inner_gap = @max(border_width*2, scroller.inner_gap+arg.i),
            .float => {},
        }
    }

    return null;
}


fn modify_master_location(state: *const kwm.State, arg: *const kwm.BindingArg) ?kwm.BindingAction {
    std.debug.assert(arg.* == .ui);

    if (state.layout == .tile) {
        tile.master_location = switch (arg.ui) {
            'l' => .left,
            'r' => .right,
            'u' => .top,
            'd' => .bottom,
            else => return null,
        };
    }

    return null;
}


fn toggle_grid_direction(state: *const kwm.State, _: *const kwm.BindingArg) ?kwm.BindingAction {
    if (state.layout == .grid) {
        grid.direction = switch (grid.direction) {
            .horizontal => .vertical,
            .vertical => .horizontal,
        };
    }

    return null;
}


fn toggle_scroller_master_location(state: *const kwm.State, arg: *const kwm.BindingArg) ?kwm.BindingAction {
    std.debug.assert(arg.* == .none);

    if (state.layout == .scroller) {
        scroller.master_location = switch (scroller.master_location) {
            .left => .center,
            .center => .left,
        };
    }

    return null;
}


fn toggle_auto_swallow(_: *const kwm.State, _: *const kwm.BindingArg) ?kwm.BindingAction {
    auto_swallow = !auto_swallow;

    return null;
}


pub const Mode = enum {
    lock, // do not delete, compile needed
    default,
    floating,
    passthrough,
};
// if not set, will use @tagName(mode) as replacement
// if set to empty string, will hide
pub const mode_tag: std.EnumMap(Mode, []const u8) = .init(.{
    .lock = "",
    .default = "",
    .floating = "F",
    .passthrough = "P",
});

pub const tags = [_][]const u8 {
    "1", "2", "3", "4", "5", "6", "7", "8", "9"
};

pub const xkb_bindings = blk: {
    const bindings = [_]XkbBinding {
        // passthrough
        .{
            .keysym = Keysym.Escape,
            .modifiers = Super|Shift,
            .action = .{ .switch_mode = .{ .mode = .passthrough } }
        },
        .{
            .mode = .passthrough,
            .keysym = Keysym.Escape,
            .modifiers = Super|Shift,
            .action = .{ .switch_mode = .{ .mode = .default } }
        },


        // floating
        .{
            .keysym = Keysym.f,
            .modifiers = Super|Ctrl,
            .action = .{ .switch_mode = .{ .mode = .floating } },
        },
        .{
            .mode = .floating,
            .keysym = Keysym.f,
            .modifiers = Super|Ctrl,
            .action = .{ .switch_mode = .{ .mode = .default } },
        },
        .{
            .mode = .floating,
            .keysym = Keysym.l,
            .modifiers = Super,
            .event = .repeat,
            .action = .{ .move = .{ .step = .{ .horizontal = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.h,
            .modifiers = Super,
            .event = .repeat,
            .action = .{ .move = .{ .step = .{ .horizontal = -10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.j,
            .modifiers = Super,
            .event = .repeat,
            .action = .{ .move = .{ .step = .{ .vertical = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.k,
            .modifiers = Super,
            .event = .repeat,
            .action = .{ .move = .{ .step = .{ .vertical = -10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.l,
            .modifiers = Super|Ctrl,
            .event = .repeat,
            .action = .{ .resize = .{ .step = .{ .horizontal = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.h,
            .modifiers = Super|Ctrl,
            .event = .repeat,
            .action = .{ .resize = .{ .step = .{ .horizontal = -10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.j,
            .modifiers = Super|Ctrl,
            .event = .repeat,
            .action = .{ .resize = .{ .step = .{ .vertical = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.k,
            .modifiers = Super|Ctrl,
            .event = .repeat,
            .action = .{ .resize = .{ .step = .{ .vertical = -10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.l,
            .modifiers = Super|Shift,
            .action = .{ .snap = .{ .edge = .right } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.h,
            .modifiers = Super|Shift,
            .action = .{ .snap = .{ .edge = .left } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.j,
            .modifiers = Super|Shift,
            .action = .{ .snap = .{ .edge = .bottom } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.k,
            .modifiers = Super|Shift,
            .action = .{ .snap = .{ .edge = .top } }
        },


        // default
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
            .keysym = Keysym.b,
            .modifiers = Super,
            .action = .toggle_bar,
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
            .modifiers = Super|Alt,
            .action = .{ .custom_fn = .{ .func = &modify_master_location, .arg = .{ .ui = 'd' } } },
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super|Alt,
            .action = .{ .custom_fn = .{ .func = &modify_master_location, .arg = .{ .ui = 'u' } } },
        },
        .{
            .keysym = Keysym.l,
            .modifiers = Super|Alt,
            .action = .{ .custom_fn = .{ .func = &modify_master_location, .arg = .{ .ui = 'r' } } },
        },
        .{
            .keysym = Keysym.h,
            .modifiers = Super|Alt,
            .action = .{ .custom_fn = .{ .func = &modify_master_location, .arg = .{ .ui = 'l' } } },
        },
        .{
            .keysym = Keysym.equal,
            .modifiers = Super,
            .action = .{ .custom_fn = .{ .func = &modify_nmaster, .arg = .{ .i = 1 } } },
        },
        .{
            .keysym = Keysym.minus,
            .modifiers = Super,
            .action = .{ .custom_fn = .{ .func = &modify_nmaster, .arg = .{ .i = -1 } } },
        },
        .{
            .keysym = Keysym.equal,
            .modifiers = Super|Alt,
            .action = .{ .custom_fn = .{ .func = &modify_gap, .arg = .{ .i = 1 } } },
        },
        .{
            .keysym = Keysym.minus,
            .modifiers = Super|Alt,
            .action = .{ .custom_fn = .{ .func = &modify_gap, .arg = .{ .i = -1 } } },
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super,
            .action = .{ .focus_iter = .{ .direction = .forward } },
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super,
            .action = .{ .focus_iter = .{ .direction = .reverse } },
        },
        .{
            .keysym = Keysym.j,
            .modifiers = Super|Ctrl,
            .action = .{ .focus_iter = .{ .direction = .forward, .skip_floating = true, } },
        },
        .{
            .keysym = Keysym.k,
            .modifiers = Super|Ctrl,
            .action = .{ .focus_iter = .{ .direction = .reverse, .skip_floating = true } },
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
            .keysym = Keysym.period,
            .modifiers = Super|Shift,
            .action = .{ .send_to_output = .{ .direction = .forward } },
        },
        .{
            .keysym = Keysym.comma,
            .modifiers = Super|Shift,
            .action = .{ .send_to_output = .{ .direction = .reverse } },
        },
        .{
            .keysym = Keysym.m,
            .modifiers = Super|Shift,
            .action = .{ .toggle_fullscreen = .{ .in_window = true } },
        },
        .{
            .keysym = Keysym.f,
            .modifiers = Super|Shift,
            .action = .{ .toggle_fullscreen = .{} },
        },
        .{
            .keysym = Keysym.space,
            .modifiers = Super,
            .action = .toggle_floating,
        },
        .{
            .keysym = Keysym.s,
            .modifiers = Super|Shift,
            .action = .toggle_sticky,
        },
        .{
            .keysym = Keysym.a,
            .modifiers = Super,
            .action = .toggle_swallow,
        },
        .{
            .keysym = Keysym.a,
            .modifiers = Super|Shift,
            .action = .{ .custom_fn = .{ .func = &toggle_auto_swallow, .arg = .none } }
        },
        .{
            .keysym = Keysym.g,
            .modifiers = Super|Shift,
            .action = .{ .custom_fn = .{ .func = &toggle_grid_direction, .arg = .none } },
        },
        .{
            .keysym = Keysym.h,
            .modifiers = Super|Shift,
            .action = .{ .custom_fn = .{ .func = &toggle_scroller_master_location, .arg = .none } },
        },
        .{
            .keysym = Keysym.f,
            .modifiers = Super,
            .action = .{ .switch_layout = .{ .layout = .float } },
        },
        .{
            .keysym = Keysym.t,
            .modifiers = Super,
            .action = .{ .switch_layout = .{ .layout = .tile } },
        },
        .{
            .keysym = Keysym.g,
            .modifiers = Super,
            .action = .{ .switch_layout = .{ .layout = .grid } },
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
            .keysym = Keysym.Tab,
            .modifiers = Super,
            .action = .switch_to_previous_tag,
        },
        .{
            .keysym = Keysym.apostrophe,
            .modifiers = Super,
            .action = .{ .shift_tag = .{ .direction = .forward } },
        },
        .{
            .keysym = Keysym.semicolon,
            .modifiers = Super,
            .action = .{ .shift_tag = .{ .direction = .reverse } },
        },
        .{
            .keysym = Keysym.@"0",
            .modifiers = Super,
            .action = .{ .set_output_tag = .{ .tag = 0xffffffff } }
        },
        .{
            .keysym = Keysym.p,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "wmenu-run" } },
        },
        .{
            .keysym = Keysym.Return,
            .modifiers = Super|Shift,
            .action = .{ .spawn = .{ .argv = &[_][]const u8 { term_cmd } } },
        },
    };

    const tag_num = tags.len;
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

fn show_appid(state: *const kwm.State, _: *const kwm.BindingArg) ?kwm.BindingAction {
    const static = struct {
        pub var buffer: [32]u8 = undefined;
        pub var argv = [_][]const u8 { "notify-send", &buffer };
    };

    if (state.window_below_pointer) |window| {
        static.argv[1] = fmt.bufPrint(&static.buffer, "APP_ID: {s}", .{ window.app_id orelse "NULL" }) catch return null;
        return .{ .spawn = .{ .argv = &static.argv } };
    }
    return null;
}

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
    .{
        .button = .middle,
        .modifiers = Super,
        .action = .{ .custom_fn = .{ .func = &show_appid, .arg = .none } },
    }
};


//  rules
//  support regex by: https://github.com/mnemnion/mvzr
// .{
//     // match part
//     .{
//         .str = "pattern",
//         .regex = true, // regex with .str
//         .match_null = true, // will match null
//     }

pub const window_rules = [_]rule.Window {
    //     // apply part
    //     .tag = 1,
    //     .floating = true,
    //     .dimension = .{ .width = 640, .height = 480 },
    //     .decoration = .csd or .ssd
    //     .is_terminal = true,
    //     .disable_swallow = true,
    //     .scroller_mfact = 0.5
    // },
    .{ .app_id = .{ .str = "", .match_null = true }, .title = .{ .str = "", .match_null = true }, .floating = true },
    .{ .app_id = .{ .str = "zenity" }, .floating = true },
    .{ .app_id = .{ .str = "DesktopEditors" }, .floating = true },
    .{ .app_id = .{ .str = "xdg-desktop-portal-gtk" }, .floating = true },
    .{ .app_id = .{ .str = "chromium" }, .tag = 1 << 1, .scroller_mfact = 0.9 },
    .{ .app_id = .{ .str = "foot" }, .is_terminal = true, .scroller_mfact = 0.8 },
};

pub const input_device_rules = [_]rule.InputDevice {
    .{ .name = .{ .str = ".*", .regex = true }, .repeat_info = .{ .rate = repeat_rate, .delay = repeat_delay } },
};

pub const libinput_device_rules = [_]rule.LibinputDevice {
    .{ .name = .{ .str = ".*[tT]ouchpad", .regex = true }, .natural_scroll = .enabled },
    .{ .name = .{ .str = ".*", .regex = true }, .tap = .enabled, .drag = .enabled }
};

pub const xkb_keyboard_rules = [_]rule.XkbKeyboard {
    //
};
