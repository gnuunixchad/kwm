const Self = @This();

const std = @import("std");
const log = std.log.scoped(.seat);

const xkb = @import("xkbcommon");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils.zig");
const config = @import("config.zig");
const binding = @import("binding.zig");
const Window = @import("window.zig");
const Context = @import("context.zig");

const Event = union(enum) {
    enable: config.seat.Mode,
    disable: config.seat.Mode,
};


link: wl.list.Link = undefined,

rwm_seat: *river.SeatV1,
rwm_layer_shell_seat: *river.LayerShellSeatV1,

unhandled_events: std.ArrayList(Event) = .empty,
focus_exclusive: bool = false,
unhandled_actions: std.ArrayList(binding.Action) = .empty,
xkb_bindings: std.EnumMap(config.seat.Mode, std.ArrayList(binding.XkbBinding)) = undefined,
pointer_bindings: std.EnumMap(config.seat.Mode, std.ArrayList(binding.PointerBinding)) = undefined,


pub fn create(rwm_seat: *river.SeatV1) !*Self {
    const seat = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(seat);

    defer log.debug("<{*}> created", .{ seat });

    const context = Context.get();

    const rwm_layer_shell_seat = try context.rwm_layer_shell.getSeat(rwm_seat);

    seat.* = .{
        .rwm_seat = rwm_seat,
        .rwm_layer_shell_seat = rwm_layer_shell_seat,
        .xkb_bindings = .init(.{}),
        .pointer_bindings = .init(.{}),
    };
    seat.link.init();
    try seat.unhandled_events.append(utils.allocator, .{ .enable = context.mode });

    for (config.seat.xkb_bindings) |xkb_binding| {
        if (!seat.xkb_bindings.contains(xkb_binding.mode)) {
            seat.xkb_bindings.put(xkb_binding.mode, .empty);
        }
        const list = seat.xkb_bindings.getPtr(xkb_binding.mode).?;
        const ptr = try list.addOne(utils.allocator);
        try ptr.init(
            seat,
            xkb_binding.keysym,
            xkb_binding.modifiers,
            xkb_binding.action,
            xkb_binding.event,
        );
    }

    for (config.seat.pointer_bindings) |pointer_binding| {
        if (!seat.pointer_bindings.contains(pointer_binding.mode)) {
            seat.pointer_bindings.put(pointer_binding.mode, .empty);
        }
        const list = seat.pointer_bindings.getPtr(pointer_binding.mode).?;
        const ptr = try list.addOne(utils.allocator);
        try ptr.init(
            seat,
            pointer_binding.button,
            pointer_binding.modifiers,
            pointer_binding.action,
            pointer_binding.event,
        );
    }

    rwm_seat.setListener(*Self, rwm_seat_listener, seat);
    rwm_layer_shell_seat.setListener(*Self, rwm_layer_shell_seat_listener, seat);

    return seat;
}


pub fn destroy(self: *Self) void {
    defer log.debug("<{*}> destroied", .{ self });

    self.link.remove();
    self.rwm_seat.destroy();

    for (&self.xkb_bindings.values) |*list| {
        for (list.items) |*xkb_binding| {
            xkb_binding.deinit();
        }
        list.deinit(utils.allocator);
    }

    for (&self.pointer_bindings.values) |*list| {
        for (list.items) |*pointer_binding| {
            pointer_binding.deinit();
        }
        list.deinit(utils.allocator);
    }

    self.unhandled_events.deinit(utils.allocator);
    self.unhandled_actions.deinit(utils.allocator);

    utils.allocator.destroy(self);
}


pub fn prepare_switch_mode(self: *Self, mode: config.seat.Mode) void {
    log.debug("<{*}> prepare switch to mode: {s}", .{ self, @tagName(mode) });

    self.unhandled_events.append(utils.allocator, .{ .switch_mode = mode }) catch |err| {
        log.err("<{*}> append event {s} failed: {}", .{ self, @tagName(mode), err });
        return;
    };
}


pub inline fn op_start(self: *Self) void {
    log.debug("<{*}> op begin", .{ self });

    self.rwm_seat.opStartPointer();
}


pub inline fn op_end(self: *Self) void {
    log.debug("<{*}> op end", .{ self });

    self.rwm_seat.opEnd();
}


pub fn manage(self: *Self) void {
    defer log.debug("<{*}> managed", .{ self });

    const context = Context.get();

    self.handle_events();

    self.handle_bindings();

    self.rwm_seat.clearFocus();
    if (!self.focus_exclusive) {
        if (context.focused()) |window| {
            self.rwm_seat.focusWindow(window.rwm_window);
        }
    }
}


fn handle_events(self: *Self) void {
    defer self.unhandled_events.clearRetainingCapacity();

    for (self.unhandled_events.items) |event| {
        log.debug("<{*}> handle event: {s}", .{ self, @tagName(event) });

        switch (event) {
            .enable => |mode| {
                for (self.xkb_bindings.get(mode).?.items) |*xkb_binding| {
                    xkb_binding.enable();
                }
                for (self.pointer_bindings.get(mode).?.items) |*pointer_binding| {
                    pointer_binding.enable();
                }
            },
            .disable => |mode| {
                for (self.xkb_bindings.get(mode).?.items) |*xkb_binding| {
                    xkb_binding.disable();
                }
                for (self.pointer_bindings.get(mode).?.items) |*pointer_binding| {
                    pointer_binding.disable();
                }
            }
        }
    }
}


fn handle_bindings(self: *Self) void {
    defer self.unhandled_actions.clearRetainingCapacity();

    const context = Context.get();
    for (self.unhandled_actions.items) |action| {
        switch (action) {
            .quit => {
                context.rwm.stop();
            },
            .spawn => |argv| {
                context.spawn(argv);
            },
            .spawn_shell => |cmd| {
                context.spawn_shell(cmd);
            },
            .pointer_move => {
                context.focused().?.prepare_move(context.current_seat.?);
            },
            .pointer_resize => {
                context.focused().?.prepare_resize(context.current_seat.?);
            },
            else => {}
        }
    }
}


fn rwm_seat_listener(rwm_seat: *river.SeatV1, event: river.SeatV1.Event, seat: *Self) void {
    std.debug.assert(rwm_seat == seat.rwm_seat);

    const context = Context.get();

    if (seat != context.current_seat) {
        log.debug("<{*}> is not current seat, ignore event: {s}", .{ seat, @tagName(event) });
        return;
    }

    switch (event) {
        .op_delta => |data| {
            log.debug("<{*}> op delta: (dx: {}, dy: {})", .{ seat, data.dx, data.dy });

            const window = context.focused().?;
            switch (window.operator) {
                .none => unreachable,
                .move => |op_data| {
                    std.debug.assert(seat == op_data.seat);

                    window.move(
                        op_data.start_x+data.dx,
                        op_data.start_y+data.dy,
                    );
                },
                .resize => |op_data| {
                    std.debug.assert(seat == op_data.seat);

                    window.resize(op_data.start_width+data.dx, op_data.start_height+data.dy);
                }
            }
        },
        .op_release => {
            log.debug("<{*}> op release", .{ seat });

            const window = context.focused().?;
            switch (window.operator) {
                .none => {},
                .move => window.prepare_move(null),
                .resize => window.prepare_resize(null),
            }
        },
        .pointer_enter => |data| {
            log.debug("<{*}> pointer enter: {*}", .{ seat, data.window });
        },
        .pointer_leave => {
            log.debug("<{*}> pointer leave", .{ seat });
        },
        .removed => {
            log.debug("<{*}> removed", .{ seat });

            if (seat == context.current_seat) {
                context.promote_new_seat();
            }

            seat.destroy();
        },
        .shell_surface_interaction => |data| {
            log.debug("<{*}> shell surface interaction: {*}", .{ seat, data.shell_surface });
        },
        .window_interaction => |data| {
            log.debug("<{*}> window interaction: {*}", .{ seat, data.window });

            const window: *Window = @ptrCast(
                @alignCast(river.WindowV1.getUserData(data.window.?))
            );

            context.set_current_output(window.output.?);
            window.output.?.set_current(window);
        },
        .wl_seat => |data| {
            log.debug("<{*}> wl_seat: {}", .{ seat, data.name });
        },
    }
}


fn rwm_layer_shell_seat_listener(rwm_layer_shell_seat: *river.LayerShellSeatV1, event: river.LayerShellSeatV1.Event, seat: *Self) void {
    std.debug.assert(rwm_layer_shell_seat == seat.rwm_layer_shell_seat);

    switch (event) {
        .focus_exclusive => {
            log.debug("<{*}> focus exclusive", .{ seat });

            std.debug.assert(!seat.focus_exclusive);

            seat.focus_exclusive = true;
        },
        .focus_non_exclusive => {
            log.debug("<{*}> focus non exclusive", .{ seat });
        },
        .focus_none => {
            log.debug("<{*}> focus none", .{ seat });

            std.debug.assert(seat.focus_exclusive);

            seat.focus_exclusive = false;
        }
    }
}
