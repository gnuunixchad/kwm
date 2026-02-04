const Self = @This();

const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;

const wayland = @import("wayland");
const river = wayland.client.river;

const kwm = @import("kwm");

const rule = @import("config/rule.zig");

var config: ?Self = null;
const default_config: Self = @import("default_config");

pub const lock_mode = "lock";
pub const default_mode = "default";
pub const WindowRule = rule.Window;
pub const InputDeviceRule = rule.InputDevice;
pub const LibinputDeviceRule = rule.LibinputDevice;
pub const XkbKeyboardRule = rule.XkbKeyboard;


fn enum_struct(comptime E: type, comptime T: type) type {
    const info = @typeInfo(E);
    if (info != .@"enum") @panic("E is needed to be a enum");

    var fields: [info.@"enum".fields.len]std.builtin.Type.StructField = undefined;
    for (0.., info.@"enum".fields) |i, field| {
        fields[i] = std.builtin.Type.StructField {
            .name = field.name,
            .type = T,
            .is_comptime = false,
            .default_value_ptr = switch (@typeInfo(T)) {
                .optional => blk: {
                    const default_value: T = null;
                    break :blk &default_value;
                },
                else => null,
            },
            .alignment = @alignOf(T),
        };
    }

    const S = @Type(
        .{
            .@"struct" = .{
                .layout = .auto,
                .is_tuple = false,
                .fields = &fields,
                .decls = &.{},
            },
        }
    );

    const Getter = struct {
        pub const instance: @This() = .{};
        pub fn get(self: *const @This(), e: E) T {
            inline for (@typeInfo(E).@"enum".fields) |field| {
                if (@intFromEnum(e) == field.value) return @field(@as(*const S, @ptrCast(@alignCast(self))), field.name);
            }
            unreachable;
        }
    };

    return @Type(
        .{
            .@"struct" = .{
                .layout = .auto,
                .is_tuple = false,
                .fields = &([_]std.builtin.Type.StructField {.{
                    .name = "getter",
                    .type = Getter,
                    .default_value_ptr = &Getter.instance,
                    .is_comptime = false,
                    .alignment = @alignOf(T),
                }} ++ fields),
                .decls = &.{},
            },
        }
    );
}


env: []const struct { []const u8, []const u8 },

working_directory: union(enum) {
    none,
    home,
    custom: []const u8,
},

startup_cmds: []const []const []const u8,

xcursor_theme: ?struct {
    name: []const u8,
    size: u32,
},

bar: struct {
    show_default: bool,
    position: enum {
        top,
        bottom,
    },
    font: []const u8,
    color: struct {
        normal: struct {
            fg: u32,
            bg: u32,
        },
        select: struct {
            fg: u32,
            bg: u32,
        },
    },
    status: union(enum) {
        text: []const u8,
        stdin,
        fifo: []const u8,
    },
    click: enum_struct(
        kwm.BarArea,
        enum_struct(kwm.Button, ?kwm.BindingAction),
    ),
},

sloppy_focus: bool,

auto_swallow: bool,

default_window_decoration: kwm.WindowDecoration,

border: struct {
    width: i32,
    color: struct {
        focus: u32,
        unfocus: u32,
    }
},

tags: []const []const u8,

layout: struct {
    default: kwm.layout.Type,
    tile: kwm.layout.tile,
    grid: kwm.layout.grid,
    monocle: kwm.layout.monocle,
    scroller: kwm.layout.scroller,
},
layout_tag: struct {
    tile: enum_struct(kwm.layout.tile.MasterLocation, []const u8),
    grid: enum_struct(kwm.layout.grid.Direction, []const u8),
    monocle: []const u8,
    scroller: enum_struct(kwm.layout.scroller.MasterLocation, []const u8),
    float: []const u8,
},

bindings: struct {
    repeat_info: kwm.KeyboardRepeatInfo,
    mode_tag: []const struct { []const u8, []const u8 },
    key: []const struct {
        mode: []const u8 = default_mode,
        keysym: []const u8,
        modifiers: river.SeatV1.Modifiers,
        event: kwm.XkbBindingEvent,
    },
    pointer: []const struct {
        mode: []const u8 = default_mode,
        button: kwm.Button,
        modifiers: river.SeatV1.Modifiers,
        event: kwm.PointerBindingEvent,
    }
},

window_rules: []const rule.Window,
input_device_rules: []const rule.InputDevice,
libinput_device_rules: []const rule.LibinputDevice,
xkb_keyboard_rules: []const rule.XkbKeyboard,


pub inline fn get() *Self {
    if (config == null) {
        config = default_config;
    }
    return &config.?;
}


pub fn get_mode_tag(self: *const Self, mode: []const u8) ?[]const u8 {
    for (self.bindings.mode_tag) |pair| {
        const m, const t = pair;
        if (mem.eql(u8, m, mode)) return t;
    }
    return null;
}
