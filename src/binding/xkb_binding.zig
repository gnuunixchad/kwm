const Self = @This();

const std = @import("std");
const log = std.log.scoped(.xkb_binding);

const xkb = @import("xkbcommon");
const wayland = @import("wayland");
const river = wayland.client.river;

const utils = @import("../utils.zig");
const binding = @import("../binding.zig");
const Seat = @import("../seat.zig");
const Context = @import("../context.zig");


rwm_xkb_binding: *river.XkbBindingV1,

seat: *Seat,
action: binding.Action,
event: river.XkbBindingV1.Event,


pub fn init(
    self: *Self,
    seat: *Seat,
    keysym: u32,
    modifiers: river.SeatV1.Modifiers,
    action: binding.Action,
    event: river.XkbBindingV1.Event,
) !void {
    defer log.debug("<{*}> created", .{ self });

    const context = Context.get();
    const rwm_xkb_binding = try context.rwm_xkb_bindings.getXkbBinding(seat.rwm_seat, keysym, modifiers);

    self.* = .{
        .rwm_xkb_binding = rwm_xkb_binding,
        .seat = seat,
        .action = action,
        .event = event
    };

    rwm_xkb_binding.setListener(*Self, rwm_xkb_binding_listener, self);
}


pub fn deinit(self: *Self) void {
    defer log.debug("<{*}> destroied", .{ self });

    self.rwm_xkb_binding.destroy();
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

    if (
        (event == .pressed and xkb_binding.event == .released)
        or (event == .released and xkb_binding.event == .pressed)
    ) return;

    xkb_binding.seat.unhandled_actions.append(utils.allocator, xkb_binding.action) catch |err| {
        log.err("append action failed: {}", .{ err });
        return;
    };
}
