const Self = @This();

const std = @import("std");
const log = std.log.scoped(.xkb_binding);

const wayland = @import("wayland");
const river = wayland.client.river;

const utils = @import("utils");

const binding = @import("../binding.zig");
const Seat = @import("../seat.zig");
const Context = @import("../context.zig");

pub const Event = enum {
    pressed,
    released,
    repeat,
};


rwm_xkb_binding: *river.XkbBindingV1,

seat: *Seat,
action: binding.Action,
event: Event,


pub fn create(
    seat: *Seat,
    keysym: u32,
    modifiers: river.SeatV1.Modifiers,
    action: binding.Action,
    event: Event,
) !*Self {
    const xkb_binding = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(xkb_binding);

    defer log.debug("<{*}> created", .{ xkb_binding });

    const context = Context.get();
    const rwm_xkb_binding = try context.rwm_xkb_bindings.getXkbBinding(seat.rwm_seat, keysym, modifiers);

    xkb_binding.* = .{
        .rwm_xkb_binding = rwm_xkb_binding,
        .seat = seat,
        .action = action,
        .event = event
    };

    rwm_xkb_binding.setListener(*Self, rwm_xkb_binding_listener, xkb_binding);

    return xkb_binding;
}


pub fn destroy(self: *Self) void {
    defer log.debug("<{*}> destroyed", .{ self });

    self.rwm_xkb_binding.destroy();

    utils.allocator.destroy(self);
}


pub inline fn enable(self: *Self) void {
    defer log.debug("<{*}> enabled", .{ self });

    self.rwm_xkb_binding.enable();
}


pub inline fn disable(self: *Self) void {
    defer log.debug("<{*}> disabled", .{ self });

    self.rwm_xkb_binding.disable();
}


fn rwm_xkb_binding_listener(rwm_xkb_binding: *river.XkbBindingV1, event: river.XkbBindingV1.Event, xkb_binding: *Self) void {
    std.debug.assert(rwm_xkb_binding == xkb_binding.rwm_xkb_binding);

    log.debug("<{*}> {s}", .{ xkb_binding, @tagName(event) });

    switch (xkb_binding.event) {
        .pressed => if (event != .pressed) return,
        .released => if (event != .released) return,
        .repeat => {
            const context = Context.get();

            if (context.key_repeat) |*key_repeat| {
                switch (event) {
                    .pressed => {
                        key_repeat.prepare_repeat(xkb_binding);
                    },
                    .stop_repeat, .released => key_repeat.stop(xkb_binding),
                }
            }
        },
    }

    xkb_binding.seat.append_action(xkb_binding.action);
}
