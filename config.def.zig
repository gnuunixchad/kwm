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
const Rule = @import("rule");

const Alt: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod1);
const Super: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod4);
const Ctrl: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.ctrl);
const Shift: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.shift);
const Button = struct {
    const left = 0x110;
    const right = 0x111;
    const middle = 0x112;
};
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
};
const XkbBinding = struct {
    mode: Mode = .default,
    keysym: u32,
    modifiers: u32,
    event: river.XkbBindingV1.Event = .pressed,
    action: kwm.binding.Action,
};
const PointerBinding = struct {
    mode: Mode = .default,
    button: u32,
    modifiers: u32,
    action: kwm.binding.Action,
    event: river.PointerBindingV1.Event = .pressed,
};
const BorderColor = struct {
    focus: u32,
    unfocus: u32,
    urgent: u32,
};


////////////////////////////////////////////////////////
// Configure part
////////////////////////////////////////////////////////

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

pub const repeat_rate = 30;
pub const repeat_delay = 300;
pub const scroll_factor = 1.0;

pub const sloppy_focus = false;

pub const bar: BarConfig = .{
    .show_default = true,
    .position = .top,
    .font = "SourceCodePro:size=13:weight=Medium",
    .color = .{
        .normal = .{
            .fg = 0xbbbbbbff,
            .bg = 0x000000ff,
        },
        .select = .{
            .fg = 0xeeeeeeff,
            .bg = 0x427b58ff,
        },
    },
    .status = .stdin // .stdin or .{ .fifo = "fifo file path" }
};

pub var auto_swallow = true;

pub const default_window_decoration: kwm.WindowDecoration = .ssd;

pub var border_width: i32 = 2;
pub const border_color: BorderColor = .{
    .focus = 0x427b58ff,
    .unfocus = 0x000000ff,
    .urgent = 0xeeeeeeff,
};


pub const default_layout: kwm.layout.Type = .tile;
pub var tile: kwm.layout.tile = .{
    .nmaster = 1,
    .mfact = 0.50,
    .inner_gap = 0,
    .outer_gap = 0,
    .master_location = .left,
};
pub var grid: kwm.layout.grid = .{
    .outer_gap = 0,
    .inner_gap = 0,
    .direction = .horizontal,
};
pub var monocle: kwm.layout.monocle = .{
    .gap = 0,
};
pub var scroller: kwm.layout.scroller = .{
    .mfact = 0.5,
    .inner_gap = 0,
    .outer_gap = 0,
    .snap_to_left = false,
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
        .scroller => if (scroller.snap_to_left) "[<-]" else "[==]",
        .float => "><>",
    };
}


fn modify_nmaster(state: *const kwm.State, arg: *const kwm.binding.Arg) void {
    std.debug.assert(arg.* == .i);

    if (state.layout == .tile) {
        tile.nmaster = @max(1, tile.nmaster+arg.i);
    }
}


fn modify_mfact(state: *const kwm.State, arg: *const kwm.binding.Arg) void {
    std.debug.assert(arg.* == .f);

    if (state.layout) |layout_t| {
        switch (layout_t) {
            .tile => tile.mfact = @min(1, @max(0, tile.mfact+arg.f)),
            .scroller => scroller.mfact = @min(1, @max(0, scroller.mfact+arg.f)),
            else => {},
        }
    }
}


fn modify_gap(state: *const kwm.State, arg: *const kwm.binding.Arg) void {
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
}


fn modify_master_location(state: *const kwm.State, arg: *const kwm.binding.Arg) void {
    std.debug.assert(arg.* == .ui);

    if (state.layout == .tile) {
        tile.master_location = switch (arg.ui) {
            'l' => .left,
            'r' => .right,
            'u' => .top,
            'd' => .bottom,
            else => return,
        };
        state.refresh_current_bar();
    }
}


fn toggle_grid_direction(state: *const kwm.State, _: *const kwm.binding.Arg) void {
    if (state.layout == .grid) {
        grid.direction = switch (grid.direction) {
            .horizontal => .vertical,
            .vertical => .horizontal,
        };
    }
}


fn toggle_scroller_snap_to_left(state: *const kwm.State, arg: *const kwm.binding.Arg) void {
    std.debug.assert(arg.* == .none);

    if (state.layout == .scroller) {
        scroller.snap_to_left = !scroller.snap_to_left;
    }
}


fn toggle_auto_swallow(_: *const kwm.State, _: *const kwm.binding.Arg) void {
    auto_swallow = !auto_swallow;
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
            .action = .{ .move = .{ .step = .{ .horizontal = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.h,
            .modifiers = Super,
            .action = .{ .move = .{ .step = .{ .horizontal = -10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.j,
            .modifiers = Super,
            .action = .{ .move = .{ .step = .{ .vertical = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.k,
            .modifiers = Super,
            .action = .{ .move = .{ .step = .{ .vertical = -10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.l,
            .modifiers = Super|Ctrl,
            .action = .{ .resize = .{ .step = .{ .horizontal = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.h,
            .modifiers = Super|Ctrl,
            .action = .{ .resize = .{ .step = .{ .horizontal = -10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.j,
            .modifiers = Super|Ctrl,
            .action = .{ .resize = .{ .step = .{ .vertical = 10 } } }
        },
        .{
            .mode = .floating,
            .keysym = Keysym.k,
            .modifiers = Super|Ctrl,
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
            .keysym = Keysym.z,
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
            .keysym = Keysym.i,
            .modifiers = Super,
            .action = .{ .custom_fn = .{ .func = &modify_nmaster, .arg = .{ .i = 1 } } },
        },
        .{
            .keysym = Keysym.d,
            .modifiers = Super,
            .action = .{ .custom_fn = .{ .func = &modify_nmaster, .arg = .{ .i = -1 } } },
        },
        .{
            .keysym = Keysym.bracketleft,
            .modifiers = Super|Ctrl,
            .action = .{ .custom_fn = .{ .func = &modify_gap, .arg = .{ .i = 2 } } },
        },
        .{
            .keysym = Keysym.bracketright,
            .modifiers = Super|Ctrl,
            .action = .{ .custom_fn = .{ .func = &modify_gap, .arg = .{ .i = -2 } } },
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
            .keysym = Keysym.w,
            .modifiers = Super,
            .action = .toggle_swallow,
        },
        .{
            .keysym = Keysym.w,
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
            .action = .{ .custom_fn = .{ .func = &toggle_scroller_snap_to_left, .arg = .none } },
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
            .keysym = Keysym.@"0",
            .modifiers = Super,
            .action = .{ .set_output_tag = .{ .tag = 0xffffffff } }
        },
        .{
            .keysym = Keysym.p,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "wmenu-run-color" } },
        },
        .{
            .keysym = Keysym.Return,
            .modifiers = Super,
            .action = .{ .spawn = .{ .argv = &[_][]const u8 { "footclient" } } },
        },
        .{
            .keysym = Keysym.r,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "footclient sh -c 'sleep 0.03 && lf'" } },
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


fn empty_appid_or_title(_: *const Rule, app_id: ?[]const u8, title: ?[]const u8) bool {
    return app_id == null or app_id.?.len == 0 or title == null or title.?.len == 0;
}
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
    //     .is_terminal = true,
    //     .disable_swallow = true,
    //     .scroller_mfact = 0.5
    // },
    .{ .alter_match_fn = &empty_appid_or_title, .floating = true },
    .{ .app_id = .{ .str = "zenity" }, .floating = true },
    .{ .app_id = .{ .str = "DesktopEditors" }, .floating = true },
    .{ .app_id = .{ .str = "xdg-desktop-portal-gtk" }, .floating = true },
    .{ .app_id = .{ .str = "chromium" }, .tag = 1 << 1, .scroller_mfact = 0.9 },
    .{ .app_id = .{ .str = "foot" }, .is_terminal = true, .scroller_mfact = 0.8 },
};

// libinput config
fn InputConfig(comptime T: type) type {
    return struct {
        value: T,
        pattern: ?Rule.Pattern = null,
    };
}
pub const tap: InputConfig(river.LibinputDeviceV1.TapState)                                 = .{ .value = .enabled };
pub const drag: InputConfig(river.LibinputDeviceV1.DragState)                               = .{ .value = .enabled };
pub const drag_lock: InputConfig(river.LibinputDeviceV1.DragLockState)                      = .{ .value = .disabled };
pub const three_finger_drag: InputConfig(river.LibinputDeviceV1.ThreeFingerDragState)       = .{ .value = .disabled };
pub const tap_button_map: InputConfig(river.LibinputDeviceV1.TapButtonMap)                  = .{ .value = .lrm };
pub const natural_scroll: InputConfig(river.LibinputDeviceV1.NaturalScrollState)            = .{ .value = .enabled, .pattern = .compile(".*[tT]ouchpad") };
pub const disable_while_typing: InputConfig(river.LibinputDeviceV1.DwtState)                = .{ .value = .enabled };
pub const disable_while_trackpointing: InputConfig(river.LibinputDeviceV1.DwtpState)        = .{ .value = .enabled };
pub const left_handed: InputConfig(river.LibinputDeviceV1.LeftHandedState)                  = .{ .value = .disabled };
pub const middle_button_emulation: InputConfig(river.LibinputDeviceV1.MiddleEmulationState) = .{ .value = .disabled };
pub const scroll_method: InputConfig(river.LibinputDeviceV1.ScrollMethod)                   = .{ .value = .two_finger };
pub const scroll_button: InputConfig(u32)                                                   = .{ .value = Button.middle };
pub const scroll_button_lock: InputConfig(river.LibinputDeviceV1.ScrollButtonLockState)     = .{ .value = .disabled };
pub const click_method: InputConfig(river.LibinputDeviceV1.ClickMethod)                     = .{ .value = .button_areas };
pub const clickfinger_button_map: InputConfig(river.LibinputDeviceV1.ClickfingerButtonMap)  = .{ .value = .lrm };
pub const send_events_modes: InputConfig(river.LibinputDeviceV1.SendEventsModes.Enum)       = .{ .value = .enabled };
pub const accel_profile: InputConfig(river.LibinputDeviceV1.AccelProfile)                   = .{ .value = .adaptive };
pub const accel_speed: InputConfig(f64)                                                     = .{ .value = 0.0 };
pub const calibration_matrix: InputConfig(?[6]f32)                                          = .{ .value = null };
pub const rotation_angle: InputConfig(u32)                                                  = .{ .value = 0 };
