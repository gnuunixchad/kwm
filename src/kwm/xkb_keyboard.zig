const Self = @This();

const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const log = std.log.scoped(.xkb_keyboard);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config");

const utils = @import("utils.zig");
const types = @import("types.zig");
const Context = @import("context.zig");

const InputDevice = @import("input_device.zig");


link: wl.list.Link = undefined,

rwm_xkb_keyboard: *river.XkbKeyboardV1,

input_device: ?*InputDevice = null,

new: bool = true,
numlock: types.KeyboardNumlockState = undefined,
capslock: types.KeyboardCapslockState = undefined,
layout_index: u32 = undefined,
layout_name: ?[]const u8 = null,


pub fn create(rwm_xkb_keyboard: *river.XkbKeyboardV1) !*Self {
    const xkb_keyboard = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(xkb_keyboard);

    log.debug("<{*}> created", .{ xkb_keyboard });

    xkb_keyboard.* = .{
        .rwm_xkb_keyboard = rwm_xkb_keyboard,
    };
    xkb_keyboard.link.init();

    rwm_xkb_keyboard.setListener(*Self, rwm_xkb_keyboard_listener, xkb_keyboard);

    return xkb_keyboard;
}


pub fn destroy(self: *Self) void {
    log.debug("<{*}> destroyed", .{ self });

    if (self.layout_name) |name| {
        utils.allocator.free(name);
        self.layout_name = null;
    }

    self.link.remove();
    self.rwm_xkb_keyboard.destroy();

    utils.allocator.destroy(self);
}


pub fn manage(self: *Self) void {
    log.debug("<{*}> manage", .{ self });

    if (self.new) {
        self.new = false;
        self.apply_config();
    }
}


fn apply_config(self: *Self) void {
    log.debug("<{*}> apply config", .{ self });

    const cfg = switch (config.keyboard) {
        .value => |value| value,
        .func => |func| func((self.input_device orelse return).name),
    };

    if (cfg.numlock) |state| {
        if (self.numlock != state) self.set_numlock(state);
    }

    if (cfg.capslock) |state| {
        if (self.capslock != state) self.set_capslock(state);
    }

    if (cfg.layout) |layout| {
        if (switch (layout) {
            .index => |index| index != self.layout_index,
            .name => |name| self.layout_name == null or mem.order(u8, mem.span(name), self.layout_name.?) != .eq,
        }) self.set_layout(layout);
    }

    if (cfg.keymap) |keymap| blk: {
        self.set_keymap(keymap) catch |err| {
            log.err("<{*}> set keymap failed: {}", .{ self, err });
            break :blk;
        };
    }
}


fn set_numlock(self: *Self, state: types.KeyboardNumlockState) void {
    log.debug("<{*}> set numlock: {s}", .{ self, @tagName(state) });

    switch (state) {
        .enabled => self.rwm_xkb_keyboard.numlockEnable(),
        .disabled => self.rwm_xkb_keyboard.numlockDisable(),
    }
}


fn set_capslock(self: *Self, state: types.KeyboardCapslockState) void {
    log.debug("<{*}> set capslock: {s}", .{ self, @tagName(state) });

    switch (state) {
        .enabled => self.rwm_xkb_keyboard.capslockEnable(),
        .disabled => self.rwm_xkb_keyboard.capslockDisable(),
    }
}


fn set_layout(self: *Self, layout: types.KeyboardLayout) void {
    switch (layout) {
        .index => |index| {
            log.debug("<{*}> set keyboard layout to {}", .{ self, index });

            self.rwm_xkb_keyboard.setLayoutByIndex(@intCast(index));
        },
        .name => |name| {
            log.debug("<{*}> set keyboard layout to {s}", .{ self, name });

            self.rwm_xkb_keyboard.setLayoutByName(name);
        }
    }
}


fn set_keymap(self: *Self, keymap: types.Keymap) !void {
    log.debug("<{*}> set keymap to `{s}` with format {s}", .{ self, keymap.file, @tagName(keymap.format) });

    const context = Context.get();

    if (context.rwm_xkb_config) |rwm_xkb_config| {
        const fd = try posix.open(keymap.file, .{ .ACCMODE = .RDWR }, 0);
        defer posix.close(fd);

        const xkb_keymap = try rwm_xkb_config.createKeymap(fd, keymap.format);

        self.rwm_xkb_keyboard.setKeymap(xkb_keymap);
    } else return error.MissingRiverXkbConfig;
}


inline fn get_from_config(self: *const Self, comptime T: type, cfg: *const config.InputConfig(T)) ?T {
    if (self.input_device) |input_device| {
        return switch (cfg.*) {
            .value => |value| value,
            .func => |func| func(input_device.name),
        };
    }
    return null;
}


fn rwm_xkb_keyboard_listener(rwm_xkb_keyboard: *river.XkbKeyboardV1, event: river.XkbKeyboardV1.Event, xkb_keyboard: *Self) void {
    std.debug.assert(rwm_xkb_keyboard == xkb_keyboard.rwm_xkb_keyboard);

    switch (event) {
        .input_device => |data| {
            log.debug("<{*}> input_device: {*}", .{ xkb_keyboard, data.device });

            const rwm_input_device = data.device orelse return;
            const input_device: *InputDevice = @ptrCast(@alignCast(rwm_input_device.getUserData()));

            log.debug("<{*}> input_device, name: {s}", .{ xkb_keyboard, input_device.name orelse "" });

            xkb_keyboard.input_device = input_device;
        },
        .layout => |data| {
            log.debug("<{*}> layout, index: {}, name: {s}", .{ xkb_keyboard, data.index, data.name orelse "" });

            if (xkb_keyboard.layout_name) |name| {
                utils.allocator.free(name);
                xkb_keyboard.layout_name = null;
            }

            xkb_keyboard.layout_index = data.index;
            if (data.name) |name| {
                xkb_keyboard.layout_name = utils.allocator.dupe(u8, mem.span(name)) catch null;
            }
        },
        .capslock_enabled => {
            log.debug("<{*}> capslock_enabled", .{ xkb_keyboard });

            xkb_keyboard.capslock = .enabled;
        },
        .capslock_disabled => {
            log.debug("<{*}> capslock_disabled", .{ xkb_keyboard });

            xkb_keyboard.capslock = .disabled;
        },
        .numlock_enabled => {
            log.debug("<{*}> numlock_enabled", .{ xkb_keyboard });

            xkb_keyboard.numlock = .enabled;
        },
        .numlock_disabled => {
            log.debug("<{*}> numlock_disabled", .{ xkb_keyboard });

            xkb_keyboard.numlock = .disabled;
        },
        .removed => {
            log.debug("<{*}> removed", .{ xkb_keyboard });

            xkb_keyboard.destroy();
        }
    }
}
