const Self = @This();

const build_options = @import("build_options");
const std = @import("std");
const log = std.log.scoped(.seat);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const config = @import("config");
const utils = @import("utils");

const binding = @import("binding.zig");
const Window = @import("window.zig");
const Context = @import("context.zig");
const ShellSurface = @import("shell_surface.zig");


link: wl.list.Link = undefined,

rwm_seat: *river.SeatV1,
rwm_layer_shell_seat: *river.LayerShellSeatV1,

mode: ?config.Mode = null,
focus_exclusive: bool = false,
pointer_position: struct {
    x: i32, y: i32,
} = undefined,
window_below_pointer: ?*Window = null,
unhandled_actions: std.ArrayList(binding.Action) = undefined,
xkb_bindings: std.EnumMap(config.Mode, std.ArrayList(*binding.XkbBinding)) = undefined,
pointer_bindings: std.EnumMap(config.Mode, std.ArrayList(*binding.PointerBinding)) = undefined,


pub fn create(rwm_seat: *river.SeatV1) !*Self {
    const seat = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(seat);

    defer log.debug("<{*}> created", .{ seat });

    const context = Context.get();

    const rwm_layer_shell_seat = try context.rwm_layer_shell.getSeat(rwm_seat);
    errdefer rwm_layer_shell_seat.destroy();

    seat.* = .{
        .rwm_seat = rwm_seat,
        .rwm_layer_shell_seat = rwm_layer_shell_seat,
        .unhandled_actions = try .initCapacity(utils.allocator, 2),
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

    if (config.xcursor_theme) |xcursor_theme| {
        rwm_seat.setXcursorTheme(xcursor_theme.name, xcursor_theme.size);
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


pub fn manage(self: *Self) void {
    defer log.debug("<{*}> managed", .{ self });

    const context = Context.get();

    if (self.mode != context.mode) {
        defer self.mode = context.mode;

        if (self.mode) |mode| {
            self.toggle_bindings(mode, false);
        }
        self.toggle_bindings(context.mode, true);
    }

    self.handle_actions();

    self.rwm_seat.clearFocus();
}


pub fn try_focus(self: *Self) void {
    log.debug("<{*}> try focus", .{ self });

    const context = Context.get();

    self.rwm_seat.clearFocus();
    if (context.focused_window()) |window| {
        self.rwm_seat.focusWindow(window.rwm_window);
    }
}


fn handle_actions(self: *Self) void {
    defer self.unhandled_actions.clearRetainingCapacity();

    const context = Context.get();
    for (self.unhandled_actions.items) |action| {
        switch (action) {
            .quit => {
                context.quit();
            },
            .close => {
                if (context.focused_window()) |window| {
                    window.prepare_close();
                }
            },
            .spawn => |data| {
                _ = context.spawn(data.argv);
            },
            .spawn_shell => |data| {
                _ = context.spawn_shell(data.cmd);
            },
            .move => |data| {
                if (context.focused_window()) |window| {
                    window.ensure_floating();
                    switch (data.step) {
                        .horizontal => |offset| window.move(window.x+offset, null),
                        .vertical => |offset| window.move(null, window.y+offset),
                    }
                }
            },
            .resize => |data| {
                if (context.focused_window()) |window| {
                    window.ensure_floating();
                    switch (data.step) {
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
            .snap => |data| {
                if (context.focused_window()) |window| {
                    window.ensure_floating();
                    window.snap_to(data.edge);
                }
            },
            .switch_mode => |data| {
                context.switch_mode(data.mode);
            },
            .focus_iter => |data| {
                context.focus_iter(data.direction, data.skip_floating);
            },
            .focus_output_iter => |data| {
                context.focus_output_iter(data.direction);
            },
            .send_to_output => |data| {
                if (context.focused_window()) |window| {
                    context.send_to_output(window, data.direction);
                }
            },
            .swap => |data| {
                context.swap(data.direction);
            },
            .toggle_fullscreen => |data| {
                context.toggle_fullscreen(data.in_window);
            },
            .set_output_tag => |data| {
                if (context.current_output) |output| {
                    output.set_tag(data.tag);
                }
            },
            .set_window_tag => |data| {
                if (context.focused_window()) |window| {
                    window.set_tag(data.tag);
                }
            },
            .toggle_output_tag => |data| {
                if (context.current_output) |output| {
                    output.toggle_tag(data.mask);
                }
            },
            .toggle_window_tag => |data| {
                if (context.focused_window()) |window| {
                    window.toggle_tag(data.mask);
                }
            },
            .switch_to_previous_tag => {
                if (context.current_output) |output| {
                    output.switch_to_previous_tag();
                }
            },
            .shift_tag => |step| {
                if (context.current_output) |output| {
                    output.shift_tag(step);
                }
            },
            .toggle_floating => {
                if (context.focused_window()) |window| {
                    window.toggle_floating();
                }
            },
            .toggle_swallow => {
                if (context.focused_window()) |window| {
                    window.toggle_swallow();
                }
            },
            .zoom => {
                if (context.focused_window()) |window| {
                    std.debug.assert(window.output != null);

                    context.shift_to_head(window);
                    context.focus(window);
                }
            },
            .switch_layout => |data| {
                if (context.current_output) |output| {
                    output.set_current_layout(data.layout);
                }
            },
            .toggle_bar => {
                if (comptime build_options.bar_enabled) {
                    if (context.current_output) |output| {
                        output.bar.toggle();
                    }
                } else {
                    log.warn("`toggle_bar` while bar disabled", .{});
                }
            },
            .custom_fn => |data| {
                const state = context.state();
                data.func(&state, &data.arg);
            }
        }
    }
}


fn window_interaction(self: *Self, window: *Window) void {
    log.debug("<{*}> interaction with window {*}", .{ self, window });

    const context = Context.get();

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

            if (config.sloppy_focus) {
                context.focus(window);
            }
        },
        .pointer_leave => {
            log.debug("<{*}> pointer leave", .{ seat });

            std.debug.assert(seat.window_below_pointer != null);

            seat.window_below_pointer = null;
        },
        .pointer_position => |data| {
            log.debug("<{*}> pointer position: (x: {}, y: {})", .{ seat, data.x, data.y });

            seat.pointer_position.x = data.x;
            seat.pointer_position.y = data.y;
        },
        .removed => {
            log.debug("<{*}> removed", .{ seat });

            context.prepare_remove_seat(seat);

            seat.destroy();
        },
        .shell_surface_interaction => |data| {
            log.debug("<{*}> shell surface interaction: {*}", .{ seat, data.shell_surface });

            const shell_surface: *ShellSurface = @ptrCast(
                @alignCast((data.shell_surface orelse return).getUserData())
            );

            log.debug("<{*}> interaction with {*}", .{ seat, shell_surface });

            switch (shell_surface.type) {
                .bar => |bar| if (comptime build_options.bar_enabled) {
                    log.debug("<{*}> interaction with {*}", .{ seat, bar });

                    bar.handle_click(seat);
                } else unreachable,
            }
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

            seat.focus_exclusive = true;
        },
        .focus_non_exclusive => {
            log.debug("<{*}> focus non exclusive", .{ seat });
        },
        .focus_none => {
            log.debug("<{*}> focus none", .{ seat });

            seat.focus_exclusive = false;
        }
    }
}
