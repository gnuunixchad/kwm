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


link: wl.list.Link = undefined,

rwm_seat: *river.SeatV1,
rwm_layer_shell_seat: *river.LayerShellSeatV1,

new: bool = undefined,
focus_exclusive: bool = false,
window_below_pointer: ?*Window = null,
unhandled_actions: std.ArrayList(binding.Action) = .empty,
xkb_bindings: std.EnumMap(config.Mode, std.ArrayList(*binding.XkbBinding)) = undefined,
pointer_bindings: std.EnumMap(config.Mode, std.ArrayList(*binding.PointerBinding)) = undefined,


pub fn create(rwm_seat: *river.SeatV1) !*Self {
    const seat = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(seat);

    defer log.debug("<{*}> created", .{ seat });

    const context = Context.get();

    const rwm_layer_shell_seat = try context.rwm_layer_shell.getSeat(rwm_seat);

    seat.* = .{
        .rwm_seat = rwm_seat,
        .rwm_layer_shell_seat = rwm_layer_shell_seat,
        .new = true,
        .xkb_bindings = .init(.{}),
        .pointer_bindings = .init(.{}),
    };
    seat.link.init();

    for (&config.xkb_bindings) |*xkb_binding| {
        log.debug("<{*}> add xkb binding: (mode: {s}, action: {any})", .{ xkb_binding, @tagName(xkb_binding.mode), xkb_binding.action });

        if (!seat.xkb_bindings.contains(xkb_binding.mode)) {
            seat.xkb_bindings.put(xkb_binding.mode, .empty);
        }
        const list = seat.xkb_bindings.getPtr(xkb_binding.mode).?;
        try list.append(
            utils.allocator,
            try binding.XkbBinding.create(
                seat,
                xkb_binding.keysym,
                @bitCast(xkb_binding.modifiers),
                xkb_binding.action,
                xkb_binding.event,
            ),
        );
    }

    for (&config.pointer_bindings) |*pointer_binding| {
        log.debug("<{*}> add pointer binding: (mode: {s}, action: {any})", .{ pointer_binding, @tagName(pointer_binding.mode), pointer_binding.action });

        if (!seat.pointer_bindings.contains(pointer_binding.mode)) {
            seat.pointer_bindings.put(pointer_binding.mode, .empty);
        }
        const list = seat.pointer_bindings.getPtr(pointer_binding.mode).?;
        try list.append(
            utils.allocator,
            try binding.PointerBinding.create(
                seat,
                pointer_binding.button,
                @bitCast(pointer_binding.modifiers),
                pointer_binding.action,
                pointer_binding.event,
            ),
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
    self.rwm_layer_shell_seat.destroy();

    {
        var it = self.xkb_bindings.iterator();
        while (it.next()) |pair| {
            for (pair.value.items) |xkb_binding| {
                xkb_binding.destroy();
            }
            pair.value.deinit(utils.allocator);
        }
    }

    {
        var it = self.pointer_bindings.iterator();
        while (it.next()) |pair| {
            for (pair.value.items) |pointer_binding| {
                pointer_binding.destroy();
            }
            pair.value.deinit(utils.allocator);
        }
    }

    self.unhandled_actions.deinit(utils.allocator);

    utils.allocator.destroy(self);
}


pub fn toggle_bindings(self: *Self, mode: config.Mode, flag: bool) void {
    log.debug("<{*}> toggle binding: (mode: {s}, flag: {})", .{ self, @tagName(mode), flag });

    if (self.xkb_bindings.get(mode)) |list| {
        for (list.items) |xkb_binding| {
            if (flag) {
                xkb_binding.enable();
            } else {
                xkb_binding.disable();
            }
        }
    }

    if (self.pointer_bindings.get(mode)) |list| {
        for (list.items) |pointer_binding| {
            if (flag) {
                pointer_binding.enable();
            } else {
                pointer_binding.disable();
            }
        }
    }
}


pub inline fn op_start(self: *Self) void {
    log.debug("<{*}> op begin", .{ self });

    self.rwm_seat.opStartPointer();
}


pub inline fn op_end(self: *Self) void {
    log.debug("<{*}> op end", .{ self });

    self.rwm_seat.opEnd();
}


pub inline fn focus(self: *Self, window: *Window) void {
    log.debug("<{*}> focus {*}", .{ self, window });

    self.rwm_seat.focusWindow(window.rwm_window);
}


pub fn manage(self: *Self) void {
    defer log.debug("<{*}> managed", .{ self });

    const context = Context.get();

    if (self.new) {
        defer self.new = false;

        self.toggle_bindings(context.mode, true);
    }

    self.handle_bindings();

    self.rwm_seat.clearFocus();
}


fn handle_bindings(self: *Self) void {
    defer self.unhandled_actions.clearRetainingCapacity();

    const context = Context.get();
    for (self.unhandled_actions.items) |action| {
        switch (action) {
            .quit => {
                context.rwm.stop();
            },
            .close => {
                if (context.focused_window()) |window| {
                    window.prepare_close();
                }
            },
            .spawn => |argv| {
                context.spawn(argv);
            },
            .spawn_shell => |cmd| {
                context.spawn_shell(cmd);
            },
            .move => |step| {
                if (context.focused_window()) |window| {
                    switch (step) {
                        .horizontal => |offset| window.move(window.x+offset, null),
                        .vertical => |offset| window.move(null, window.y+offset),
                    }
                }
            },
            .resize => |step| {
                if (context.focused_window()) |window| {
                    switch (step) {
                        .horizontal => |offset| {
                            window.move(window.x-@divFloor(offset, 2), null);
                            window.resize(window.width+offset, null);
                        },
                        .vertical => |offset| {
                            window.move(null, window.y-@divFloor(offset, 2));
                            window.resize(null, window.height+offset);
                        }
                    }
                }
            },
            .pointer_move => {
                if (self.window_below_pointer) |window| {
                    self.window_interaction(window);
                    window.prepare_move(self);
                }
            },
            .pointer_resize => {
                if (self.window_below_pointer) |window| {
                    self.window_interaction(window);
                    window.prepare_resize(self);
                }
            },
            .snap => |edges| {
                if (context.focused_window()) |window| {
                    window.snap_to(edges);
                }
            },
            .switch_mode => |mode| {
                context.switch_mode(mode);
            },
            .toggle_fullscreen => |data| {
                context.toggle_fullscreen(data.in_window);
            },
            .set_output_tag => |tag| {
                if (context.current_output) |output| {
                    output.set_tag(tag);
                }
            },
            .set_window_tag => |tag| {
                if (context.focused_window()) |window| {
                    window.set_tag(tag);
                }
            },
            .toggle_output_tag => |tag| {
                if (context.current_output) |output| {
                    output.toggle_tag(tag);
                }
            },
            .toggle_window_tag => |tag| {
                if (context.focused_window()) |window| {
                    window.toggle_tag(tag);
                }
            },
        }
    }
}


fn window_interaction(self: *Self, window: *Window) void {
    log.debug("<{*}> interaction with window {*}", .{ self, window });

    const context = Context.get();

    context.set_current_output(window.output.?);
    context.focus(window);
}


fn rwm_seat_listener(rwm_seat: *river.SeatV1, event: river.SeatV1.Event, seat: *Self) void {
    std.debug.assert(rwm_seat == seat.rwm_seat);

    const context = Context.get();

    switch (event) {
        .op_delta => |data| {
            log.debug("<{*}> op delta: (dx: {}, dy: {})", .{ seat, data.dx, data.dy });

            const window = context.focused_window().?;
            switch (window.operator) {
                .none => unreachable,
                .move => |op_data| {
                    if (op_data.seat == seat) {
                        window.move(
                            op_data.start_x+data.dx,
                            op_data.start_y+data.dy,
                        );
                    }
                },
                .resize => |op_data| {
                    if (op_data.seat == seat) {
                        window.resize(
                            op_data.start_width+data.dx,
                            op_data.start_height+data.dy,
                        );
                    }
                }
            }
        },
        .op_release => {
            log.debug("<{*}> op release", .{ seat });

            if (context.focused_window()) |window| {
                switch (window.operator) {
                    .none => {},
                    .move => |data| {
                        if (data.seat == seat) {
                            window.prepare_move(null);
                        }
                    },
                    .resize => |data| {
                        if (data.seat == seat) {
                            window.prepare_resize(null);
                        }
                    }
                }
            } else {
                log.debug("no window focused", .{});
            }
        },
        .pointer_enter => |data| {
            log.debug("<{*}> pointer enter: {*}", .{ seat, data.window });

            const rwm_window = data.window orelse return;

            const window: *Window = @ptrCast(
                @alignCast(river.WindowV1.getUserData(rwm_window))
            );

            std.debug.assert(seat.window_below_pointer == null);

            seat.window_below_pointer = window;
        },
        .pointer_leave => {
            log.debug("<{*}> pointer leave", .{ seat });

            std.debug.assert(seat.window_below_pointer != null);

            seat.window_below_pointer = null;
        },
        .pointer_position => |data| {
            log.debug("<{*}> pointer position: (x: {}, y: {})", .{ seat, data.x, data.y });
        },
        .removed => {
            log.debug("<{*}> removed", .{ seat });

            context.prepare_remove_seat(seat);

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

            seat.window_interaction(window);
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
