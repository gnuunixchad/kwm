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
    click: std.EnumMap(enum { tag, layout, mode, title, status }, std.EnumMap(Button, kwm.binding.Action)),
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
    button: Button,
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

const term_cmd = "footclient";

pub const env = [_] struct { []const u8, []const u8 } {
    // .{ "key", "value" },
};

pub const working_directory: union(enum) {
    none,
    home,
    custom: []const u8,
} = .home;

pub const startup_cmds = [_][]const []const u8 {
    &[_][]const u8 { "sh", "-c", "fcitx5 -d --verbose '*=0'" },
    &[_][]const u8 { "swayidle" },
    &[_][]const u8 { "gammastep", "-O", "5000" },
    &[_][]const u8 { "wl-paste", "--watch", "cliphist", "store" },
    &[_][]const u8 { "kanshi" },
    &[_][]const u8 { "sh", "-c", "swaybg -i ${HOME}/.local/share/wallpaper -m fill" },
    &[_][]const u8 { "dunst" },
    &[_][]const u8 { "foot", "--server" },
    &[_][]const u8 { "sh", "-c", "${HOME}/.local/bin/lucia -d" },
    &[_][]const u8 { "sh", "-c", "${HOME}/.local/bin/wobd" },
    &[_][]const u8 { "sh", "-c", "${HOME}/.local/bin/mbs-cron" },
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
    .status = .{ .fifo = "/run/user/1000/damblocks.fifo" }, // .stdin or .{ .fifo = "fifo file path" }
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
    .outer_gap = 2,
    .master_location = .left,
};
pub var grid: kwm.layout.grid = .{
    .outer_gap = 2,
    .inner_gap = 0,
    .direction = .horizontal,
};
pub var monocle: kwm.layout.monocle = .{
    .gap = 2,
};
pub var scroller: kwm.layout.scroller = .{
    .mfact = 0.5,
    .inner_gap = 0,
    .outer_gap = 2,
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

        // lock
        .{
            .mode = .lock,
            .keysym = Keysym.space,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "mpc toggle" } },
        },
        .{
            .mode = .lock,
            .keysym = Keysym.p,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "mpc prev" } },
        },
        .{
            .mode = .lock,
            .keysym = Keysym.n,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "mpc next" } },
        },
        .{
            .mode = .lock,
            .keysym = Keysym.minus,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio sink --minus10" } },
        },
        .{
            .mode = .lock,
            .keysym = Keysym.equal,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio sink --plus10" } },
        },
        .{
            .mode = .lock,
            .keysym = Keysym.bracketleft,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --minus10" } },
        },
        .{
            .mode = .lock,
            .keysym = Keysym.bracketright,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --plus10" } },
        },

        // default
        .{
            .keysym = Keysym.q,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/exiland -river" } },
        },
        .{
            .keysym = Keysym.w,
            .modifiers = Super|Shift,
            .action = .{ .spawn = .{ .argv = &[_][]const u8 { "swaylock" } } },
        },
        .{
            .keysym = Keysym.e,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/hibe" } },
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
            .keysym = Keysym.w,
            .modifiers = Super,
            .action = .{ .toggle_fullscreen = .{ .in_window = true } },
        },
        .{
            .keysym = Keysym.e,
            .modifiers = Super,
            .action = .{ .toggle_fullscreen = .{} },
        },
        .{
            .keysym = Keysym.space,
            .modifiers = Super,
            .action = .toggle_floating,
        },
        .{
            .keysym = Keysym.o,
            .modifiers = Super,
            .action = .toggle_swallow,
        },
        .{
            .keysym = Keysym.o,
            .modifiers = Super|Shift,
            .action = .{ .custom_fn = .{ .func = &toggle_auto_swallow, .arg = .none } }
        },
        .{
            .keysym = Keysym.y,
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
            .keysym = Keysym.y,
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
            .action = .{ .spawn_shell = .{ .cmd = "wmenu-run-color" } },
        },
        .{
            .keysym = Keysym.Return,
            .modifiers = Super,
            .action = .{ .spawn = .{ .argv = &[_][]const u8 { term_cmd } } },
        },
        .{
            .keysym = Keysym.v,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "footclient -T \"Floating_Term\" -o colors.alpha=0.9 abduco -A dvtm dvtm-status" } },
        },
        .{
            .keysym = Keysym.r,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "footclient sh -c 'sleep 0.03 && lf'" } },
        },
        .{
            .keysym = Keysym.q,
            .modifiers = Super,
            .action = .{ .spawn = .{ .argv = &[_][]const u8 { "qutebrowser" } } },
        },
        .{
            .keysym = Keysym.minus,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio sink --minus10" } },
        },
        .{
            .keysym = Keysym.equal,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio sink --plus10" } },
        },
        .{
            .keysym = Keysym.minus,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio sink --minus" } },
        },
        .{
            .keysym = Keysym.equal,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio sink --plus" } },
        },
        .{
            .keysym = Keysym.BackSpace,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio sink --mute" } },
        },
        .{
            .keysym = Keysym.minus,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio source --minus10" } },
        },
        .{
            .keysym = Keysym.equal,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio source --plus10" } },
        },
        .{
            .keysym = Keysym.minus,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio source --minus" } },
        },
        .{
            .keysym = Keysym.equal,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio source --plus" } },
        },
        .{
            .keysym = Keysym.BackSpace,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/audio source --mute" } },
        },
        .{
            .keysym = Keysym.bracketleft,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --minus10" } },
        },
        .{
            .keysym = Keysym.bracketright,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --plus10" } },
        },
        .{
            .keysym = Keysym.bracketleft,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --minus" } },
        },
        .{
            .keysym = Keysym.bracketright,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --plus" } },
        },
        .{
            .keysym = Keysym.bracketleft,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --min" } },
        },
        .{
            .keysym = Keysym.bracketright,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/bright --max" } },
        },
        .{
            .keysym = Keysym.m,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "pgrep hyprmag && killall -e hyprmag || hyprmag -r 9999 -s 2" } },
        },
        .{
            .keysym = Keysym.m,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "pgrep hyprmag && killall -e hyprmag || hyprmag" } },
        },
        .{
            .keysym = Keysym.space,
            .modifiers = Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "fcitx5-remote -t" } },
        },
        .{
            .keysym = Keysym.n,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "dunstctl history-pop" } },
        },
        .{
            .keysym = Keysym.n,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "dunstctl close" } },
        },
        .{
            .keysym = Keysym.n,
            .modifiers = Super|Ctrl|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "dunstctl close-all" } },
        },
        .{
            .keysym = Keysym.g,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/shoot" } },
        },
        .{
            .keysym = Keysym.g,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/shoot --geo" } },
        },
        .{
            .keysym = Keysym.g,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/shoot --all" } },
        },
        .{
            .keysym = Keysym.c,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/clip" } },
        },
        .{
            .keysym = Keysym.a,
            .modifiers = Super,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/address" } },
        },
        .{
            .keysym = Keysym.a,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/address --record" } },
        },
        .{
            .keysym = Keysym.a,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/address --multi" } },
        },
        .{
            .keysym = Keysym.space,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "mpc toggle && ${HOME}/.local/bin/lsmus" } },
        },
        .{
            .keysym = Keysym.p,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "mpc prev" } },
        },
        .{
            .keysym = Keysym.n,
            .modifiers = Super|Ctrl,
            .action = .{ .spawn_shell = .{ .cmd = "mpc next" } },
        },
        .{
            .keysym = Keysym.s,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "${HOME}/.local/bin/wsk" } },
        },
        .{
            .keysym = Keysym.b,
            .modifiers = Super|Shift,
            .action = .{ .spawn_shell = .{ .cmd = "pgrep gammastep && killall gammastep || gammastep -O 5000" } },
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
            .modifiers = Ctrl,
            .action = .{ .toggle_output_tag = .{ .mask = 1 << i } },
        };
        tag_binddings[i*4+3] = .{
            .keysym = Keysym.@"1"+i,
            .modifiers = Super|Ctrl,
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
    .{ .title = .{ .str = "Floating_Term" }, .floating = true },
    .{ .title = .{ .str = "Floating_IMG" }, .floating = true },
    // GIMP
    .{ .app_id = .compile("file-*"), .floating = true },
    .{ .title = .{ .str = "script-fu" }, .floating = true },
    .{ .app_id = .{ .str = "lighting" }, .title = .{ .str = "Lighting Effects" }, .floating = true },
    // Kdenlive file chooser
    .{ .app_id = .{ .str = "kdenlive" }, .floating = true },
    // Code - OSS
    .{ .app_id = .{ .str = "electron" }, .title = .{ .str = "Open Folder" }, .floating = true },
    .{ .app_id = .{ .str = "org.fcitx.fcitx5-config-qt" }, .floating = true },
    .{ .app_id = .{ .str = "qutebrowser" }, .tag = 1 << 1, .scroller_mfact = 0.7 },
    .{ .app_id = .{ .str = "footclient" }, .is_terminal = true, .scroller_mfact = 0.5 },
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
pub const scroll_button: InputConfig(Button)                                                = .{ .value = .middle };
pub const scroll_button_lock: InputConfig(river.LibinputDeviceV1.ScrollButtonLockState)     = .{ .value = .disabled };
pub const click_method: InputConfig(river.LibinputDeviceV1.ClickMethod)                     = .{ .value = .button_areas };
pub const clickfinger_button_map: InputConfig(river.LibinputDeviceV1.ClickfingerButtonMap)  = .{ .value = .lrm };
pub const send_events_modes: InputConfig(river.LibinputDeviceV1.SendEventsModes.Enum)       = .{ .value = .enabled };
pub const accel_profile: InputConfig(river.LibinputDeviceV1.AccelProfile)                   = .{ .value = .adaptive };
pub const accel_speed: InputConfig(f64)                                                     = .{ .value = 0.0 };
pub const calibration_matrix: InputConfig(?[6]f32)                                          = .{ .value = null };
pub const rotation_angle: InputConfig(u32)                                                  = .{ .value = 0 };
