const Self = @This();

const std = @import("std");
const log = std.log.scoped(.pointer_binding);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("../utils.zig");
const binding = @import("../binding.zig");
const Seat = @import("../seat.zig");


rwm_pointer_binding: *river.PointerBindingV1,

seat: *Seat,
action: binding.Action,
event: river.PointerBindingV1.Event,


pub fn create(
    seat: *Seat,
    button: u32,
    modifiers: river.SeatV1.Modifiers,
    action: binding.Action,
    event: river.PointerBindingV1.Event,
) !*Self {
    const pointer_binding = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(pointer_binding);

    defer log.debug("<{*}> created", .{ pointer_binding });

    const rwm_pointer_binding = try seat.rwm_seat.getPointerBinding(button, modifiers);

    pointer_binding.* = .{
        .rwm_pointer_binding = rwm_pointer_binding,
        .seat = seat,
        .action = action,
        .event = event,
    };

    rwm_pointer_binding.setListener(*Self, rwm_pointer_binding_listener, pointer_binding);

    return pointer_binding;
}


pub fn destroy(self: *Self) void {
    defer log.debug("<{*}> destroied", .{ self });

    self.rwm_pointer_binding.destroy();

    utils.allocator.destroy(self);
}


pub inline fn enable(self: *Self) void {
    defer log.debug("<{*}> enabled", .{ self });

    self.rwm_pointer_binding.enable();
}


pub inline fn disable(self: *Self) void {
    defer log.debug("<{*}> disabled", .{ self });

    self.rwm_pointer_binding.disable();
}


fn rwm_pointer_binding_listener(rwm_pointer_binding: *river.PointerBindingV1, event: river.PointerBindingV1.Event, pointer_binding: *Self) void {
    std.debug.assert(rwm_pointer_binding == pointer_binding.rwm_pointer_binding);

    log.debug("<{*}> {s}", .{ pointer_binding, @tagName(event) });

    if (
        (event == .pressed and pointer_binding.event == .released)
        or (event == .released and pointer_binding.event == .pressed)
    ) return;

    pointer_binding.seat.unhandled_actions.append(utils.allocator, pointer_binding.action) catch |err| {
        log.err("append action failed: {}", .{ err });
        return;
    };
}
