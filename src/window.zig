const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.window);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils.zig");
const config = @import("config.zig");
const Seat = @import("seat.zig");
const Output = @import("output.zig");
const Context = @import("context.zig");

const Event = union(enum) {
    init,
    title,
    app_id,
    decoration_hint: river.WindowV1.DecorationHint,
    fullscreen: ?*Output,
    maximize: bool,
    move: ?*Seat,
    resize: ?*Seat,
};


link: wl.list.Link = undefined,

rwm_window: *river.WindowV1,
rwm_window_node: *river.NodeV1,

output: ?*Output,
former_output: ?u32 = null,

unhandled_events: std.ArrayList(Event) = undefined,

fullscreen: bool = false,
maximize: bool = false,
floating: bool = false,

tag: u32,
app_id: ?[]const u8 = null,
title: ?[]const u8 = null,
parent: ?*Self = null,
decoration: ?enum(u1) {
    csd,
    ssd,
} = null,

x: i32 = undefined,
y: i32 = undefined,
width: i32 = undefined,
height: i32 = undefined,
operator: union(enum) {
    none,
    move: struct {
        start_x: i32,
        start_y: i32,
        seat: *Seat,
    },
    resize: struct {
        start_width: i32,
        start_height: i32,
        seat: *Seat,
    },
} = .none,


pub fn create(rwm_window: *river.WindowV1, output: *Output) !*Self {
    const window = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(window);

    defer log.debug("<{*}> created", .{ window });

    const rwm_window_node = try rwm_window.getNode();

    window.* = .{
        .rwm_window = rwm_window,
        .rwm_window_node = rwm_window_node,
        .output = output,
        .unhandled_events = try .initCapacity(utils.allocator, 6),
        .tag = output.tag,
    };
    window.link.init();
    try window.unhandled_events.append(utils.allocator, .init);

    rwm_window.setListener(*Self, rwm_window_listener, window);

    return window;
}


pub fn destroy(self: *Self) void {
    defer log.debug("<{*}> destroied", .{ self });

    self.link.remove();
    self.rwm_window.destroy();
    if (self.title) |title| utils.allocator.free(title);
    if (self.app_id) |app_id| utils.allocator.free(app_id);
    self.unhandled_events.deinit(utils.allocator);

    utils.allocator.destroy(self);
}


pub fn move(self: *Self, x: ?i32, y: ?i32) void {
    defer log.debug("<{*}> move to (x: {}, y: {})", .{ self, self.x, self.y });

    if (x) |x_|
        self.x = @max(
            config.window.border_width,
            @min(
                x_,
                self.output.?.width-self.width-config.window.border_width
            )
        );
    if (y) |y_|
        self.y = @max(
            config.window.border_width,
            @min(
                y_,
                self.output.?.height-self.height-config.window.border_width
            )
        );
}


pub fn resize(self: *Self, width: ?i32, height: ?i32) void {
    defer log.debug(
        "<{*}> set dimensions to (width: {}, height: {})",
        .{ self, self.width, self.height },
    );

    if (width) |w| self.width = w;
    if (height) |h| self.height = h;
}


pub fn prepare_move(self: *Self, seat: ?*Seat) void {
    log.debug("<{*}> prepare to move, seat: {*}", .{ self, seat });

    self.append_event(.{ .move = seat });
}


pub fn prepare_resize(self: *Self, seat: ?*Seat) void {
    log.debug("<{*}> prepare to resize, seat: {*}", .{ self, seat });

    self.append_event(.{ .resize = seat });
}


pub fn prepare_fullscreen(self: *Self, output: ?*Output) void {
    const target_output = output orelse self.output orelse {
        log.err("<{*}> unable to turn fullscreen: null target output", .{ self });
        return;
    };

    log.debug("<{*}> prepare to fullscreen on {*}", .{ self, target_output });

    self.append_event(.{ .fullscreen = target_output });
}


pub fn prepare_unfullscreen(self: *Self) void {
    log.debug("<{*}> prepare unfullscreen", .{ self });

    self.append_event(.{ .fullscreen = null });
}


pub fn prepare_maximize(self: *Self, flag: bool) void {
    log.debug("<{*}> prepare to maximize: {}", .{ self, flag });

    self.append_event(.{ .maximize = flag });
}


pub fn set_border(self: *Self, width: i32, rgb: u32) void {
    log.debug("<{*}> set border: (width: {}, color: 0x{x})", .{ self, width, rgb });

    const color = utils.rgba(rgb);
    self.rwm_window.setBorders(
        .{
            .top = true,
            .bottom = true,
            .left = true,
            .right = true,
        },
        width,
        color.r,
        color.g,
        color.b,
        color.a,
    );
}


pub inline fn orphan(self: *Self) bool {
    return self.former_output != null;
}


pub inline fn homeless(self: *Self) bool {
    return self.output == null and self.former_output == null;
}


pub fn visiable(self: *Self, output: *Output) bool {
    if (self.homeless()) return false;

    if (self.output.? != output) return false;

    return (self.tag & output.tag) != 0;
}


pub fn manage(self: *Self) void {
    log.debug("<{*}> managing", .{ self });

    self.handle_events();

    log.debug("<{*}> propose dimensions: (width: {}, height: {})", .{ self, self.width, self.height });

    self.rwm_window.proposeDimensions(self.width, self.height);
}


pub fn render(self: *Self) void {
    log.debug("<{*}> rendering to (x: {}, y: {})", .{ self, self.x, self.y });

    self.rwm_window_node.setPosition(
        self.output.?.x + self.x,
        self.output.?.y + self.y,
    );
    self.rwm_window.show();
}


pub fn hide(self: *Self) void {
    log.debug("<{*}> hide", .{ self });

    self.rwm_window.hide();
}


fn append_event(self: *Self, event: Event) void {
    log.debug("<{*}> append event: {s}", .{ self, @tagName(event) });

    self.unhandled_events.append(utils.allocator, event) catch |err| {
        log.err("<{*}> append event {s} failed: {}", .{ self, @tagName(event), err });
        return;
    };
}


fn handle_events(self: *Self) void {
    defer self.unhandled_events.clearRetainingCapacity();

    for (self.unhandled_events.items) |event| {
        log.debug("<{*}> handle event: {s}", .{ self, @tagName(event) });

        switch (event) {
            .init => {
                log.debug("<{*}> managing new window", .{ self });

                self.rwm_window.setTiled(.{
                    .top = true,
                    .bottom = true,
                    .left = true,
                    .right = true,
                });

                self.rwm_window.setCapabilities(.{
                    .window_menu = false,
                    .maximize = true,
                    .fullscreen = true,
                    .minimize = false,
                });

                const decoration = self.decoration orelse .ssd;
                switch (decoration) {
                    .csd => self.rwm_window.useCsd(),
                    .ssd => self.rwm_window.useSsd(),
                }

                self.x = @divFloor(self.output.?.width, 4);
                self.y = @divFloor(self.output.?.height, 4);
                self.width = @divFloor(self.output.?.width, 2);
                self.height = @divFloor(self.output.?.height, 2);
            },
            .decoration_hint => |decoration_hint| {
                log.debug("<{*}> managing decoration hint", .{ self });

                switch (decoration_hint) {
                    .only_supports_csd => self.rwm_window.useCsd(),
                    .prefers_csd => if (self.decoration == null) self.rwm_window.useCsd(),
                    .prefers_ssd => if (self.decoration == null) self.rwm_window.useSsd(),
                    else => {}
                }
            },
            .fullscreen => |data| {
                log.debug("<{*}> managing fullscreen: {*}", .{ self, data });

                std.debug.assert(self.fullscreen != (data != null));

                if (data) |output| {
                    log.debug("<{*}> fullscreen on {*}", .{ self, output });

                    self.rwm_window.informFullscreen();
                } else {
                    log.debug("<{*}> unfullscreen", .{ self });

                    self.rwm_window.informNotFullscreen();
                }
                self.fullscreen = data != null;
            },
            .maximize => |flag| {
                log.debug("<{*}> managing maximize: {}", .{ self, flag });

                std.debug.assert(self.maximize != flag);

                if (flag) {
                    self.rwm_window.informMaximized();
                } else {
                    self.rwm_window.informUnmaximized();
                }
                self.maximize = flag;
            },
            .move => |data| {
                log.debug("<{*}> managing move, seat: {*}", .{ self, data });

                if (data) |seat| {
                    seat.op_start();
                    self.operator = .{
                        .move = .{
                            .start_x = self.x,
                            .start_y = self.y,
                            .seat = seat,
                        },
                    };
                } else {
                    switch (self.operator) {
                        .move => |op_data| {
                            op_data.seat.op_end();
                        },
                        else => unreachable,
                    }
                    self.operator = .none;
                }
            },
            .resize => |data| {
                log.debug("<{*}> managing resize, seat: {*}", .{ self, data });

                if (data) |seat| {
                    seat.op_start();
                    self.operator = .{
                        .resize = .{
                            .start_width = self.width,
                            .start_height = self.height,
                            .seat = seat,
                        },
                    };
                } else {
                    switch (self.operator) {
                        .resize => |op_data| {
                            op_data.seat.op_end();
                        },
                        else => unreachable,
                    }
                    self.operator = .none;
                }
            },
            else => {}
        }
    }
}


fn rwm_window_listener(rwm_window: *river.WindowV1, event: river.WindowV1.Event, window: *Self) void {
    std.debug.assert(rwm_window == window.rwm_window);

    switch (event) {
        .app_id => |data| {
            const app_id = data.app_id orelse return;

            log.debug("<{*}> app_id: {s}", .{ window, app_id });

            window.app_id = utils.allocator.dupe(u8, mem.span(app_id)) catch return;
        },
        .title => |data| {
            const title = data.title orelse return;

            log.debug("<{*}> title: {s}", .{ window, title });

            window.title = utils.allocator.dupe(u8, mem.span(title)) catch return;
        },
        .closed => {
            log.debug("<{*}> closed", .{window});

            if (window.output) |owner| {
                if (owner.current_window == window) {
                    owner.promote_new_window();
                }
            }

            window.destroy();
        },
        .decoration_hint => |data| {
            log.debug("<{*}> decoration hint: {s}", .{ window, @tagName(data.hint) });

            window.unhandled_events.append(utils.allocator, .{ .decoration_hint = data.hint }) catch |err| {
                log.err("<{*}> append decoration_hint event failed: {}", .{ window, err });
                return;
            };
        },
        .dimensions => |data| {
            log.debug("<{*}> dimensions: ({}, {})", .{ window, data.width, data.height });

            window.width = data.width;
            window.height = data.height;
        },
        .dimensions_hint => |data| {
            log.debug(
                "<{*}> dimensions hint: (-width/+width: {}/{}, -height/+height: {}/{})",
                .{ window, data.min_width, data.max_width, data.min_height, data.max_height },
            );
        },
        .fullscreen_requested => |data| {
            var output: ?*Output = undefined;
            if (data.output) |rwm_output| {
                output = @ptrCast(@alignCast(river.OutputV1.getUserData(rwm_output)));
            } else {
                output = window.output;
            }

            log.debug("<{*}> fullscreen requested: {*}", .{ window, output });

            window.prepare_fullscreen(output);
        },
        .exit_fullscreen_requested => {
            log.debug("<{*}> exit fullscreen requested", .{window});

            window.prepare_unfullscreen();
        },
        .maximize_requested => {
            log.debug("<{*}> maximize requested", .{window});

            window.prepare_maximize(true);
        },
        .unmaximize_requested => {
            log.debug("<{*}> unmaximize requested", .{ window });

            window.prepare_maximize(false);
        },
        .minimize_requested => {
            log.debug("<{*}> minimize requested", .{window});
        },
        .parent => |data| {
            const parent_rwm_window = data.parent orelse return;
            const parent_window: *Self = @ptrCast(@alignCast(
                river.WindowV1.getUserData(parent_rwm_window),
            ));

            log.debug("<{*}> parent: {*} (of {*})", .{ window, parent_rwm_window, parent_window });

            window.parent = parent_window;
        },
        .pointer_move_requested => |data| {
            // TODO: Find own seat.
            log.debug("<{*}> pointer move requested: {*}", .{ window, data.seat });

            if (data.seat) |rwm_seat| {
                const seat: *Seat = @ptrCast(
                    @alignCast(river.SeatV1.getUserData(rwm_seat))
                );
                window.prepare_move(seat);
            }

        },
        .pointer_resize_requested => |data| {
            // TODO: Find own seat.
            log.debug("<{*}> pointer resize requested: {*}", .{ window, data.seat });

            if (data.seat) |rwm_seat| {
                const seat: *Seat = @ptrCast(
                    @alignCast(river.SeatV1.getUserData(rwm_seat))
                );
                window.prepare_resize(seat);
            }
        },
        .show_window_menu_requested => |data| {
            log.debug("<{*}> show window menu requested: (x: {}, y: {})", .{ window, data.x, data.y });
        },
    }
}
