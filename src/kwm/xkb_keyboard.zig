const Self = @This();

const std = @import("std");
const log = std.log.scoped(.xkb_keyboard);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils");

const InputDevice = @import("input_device.zig");


link: wl.list.Link = undefined,

rwm_xkb_keyboard: *river.XkbKeyboardV1,

input_device: ?*InputDevice = null,


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

    self.link.remove();
    self.rwm_xkb_keyboard.destroy();

    utils.allocator.destroy(self);
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
        },
        .capslock_enabled => {
            log.debug("<{*}> capslock_enabled", .{ xkb_keyboard });
        },
        .capslock_disabled => {
            log.debug("<{*}> capslock_disabled", .{ xkb_keyboard });
        },
        .numlock_enabled => {
            log.debug("<{*}> numlock_enabled", .{ xkb_keyboard });
        },
        .numlock_disabled => {
            log.debug("<{*}> numlock_disabled", .{ xkb_keyboard });
        },
        .removed => {
            log.debug("<{*}> removed", .{ xkb_keyboard });

            xkb_keyboard.destroy();
        }
    }
}
