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
    unfullscreen,
    maximize: bool,
    move: ?*Seat,
    resize: ?*Seat,
};


link: wl.list.Link = undefined,
flink: wl.list.Link = undefined,

rwm_window: *river.WindowV1,
rwm_window_node: *river.NodeV1,

output: ?*Output = null,
former_output: ?u32 = null,

unhandled_events: std.ArrayList(Event) = .empty,

fullscreen: union(enum) {
    none,
    window,
    output: *Output,
} = .none,
maximize: bool = false,
floating: bool = false,

tag: u32 = 1,
app_id: ?[]const u8 = null,
title: ?[]const u8 = null,
parent: ?*Self = null,
decoration: ?enum(u1) {
    csd,
    ssd,
} = null,

x: i32 = 0,
y: i32 = 0,
width: i32 = undefined,
height: i32 = undefined,
min_width: i32 = 1,
min_height: i32 = 1,
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


pub fn create(rwm_window: *river.WindowV1) !*Self {
    const window = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(window);

    defer log.debug("<{*}> created", .{ window });

    const rwm_window_node = try rwm_window.getNode();

    window.* = .{
        .rwm_window = rwm_window,
        .rwm_window_node = rwm_window_node,
    };
    window.link.init();
    window.flink.init();
    try window.unhandled_events.append(utils.allocator, .init);

    rwm_window.setListener(*Self, rwm_window_listener, window);

    return window;
}


pub fn destroy(self: *Self) void {
    defer log.debug("<{*}> destroied", .{ self });

    self.link.remove();
    self.flink.remove();
    self.rwm_window.destroy();
    self.set_appid(null);
    self.set_title(null);
    self.unhandled_events.deinit(utils.allocator);

    utils.allocator.destroy(self);
}


pub fn set_output(self: *Self, output: ?*Output) void {
    log.debug("<{*}> set output to {*}", .{ self, output });

    self.output = output;
}


pub fn set_former_output(self: *Self, output: ?u32) void {
    log.debug("<{*}> set former output to {?}", .{ self, output });

    self.former_output = output;
}


pub fn set_tag(self: *Self, tag: u32) void {
    if (tag == 0) return;

    log.debug("<{*}> set tag: {b}", .{ self, tag });

    self.tag = tag;
}


pub fn toggle_tag(self: *Self, mask: u32) void {
    if (self.tag ^ mask == 0) return;

    log.debug("<{*}> toggle tag: {b}", .{ self, mask });

    self.tag ^= mask;
}


pub fn place(self: *Self, pos: union(enum) {
    top,
    bottom,
    above: *Self,
    below: *Self,
}) void {
    switch (pos) {
        .top => self.rwm_window_node.placeTop(),
        .bottom => self.rwm_window_node.placeBottom(),
        .above => |window| self.rwm_window_node.placeAbove(window.rwm_window_node),
        .below => |window| self.rwm_window_node.placeBelow(window.rwm_window_node),
    }
}


pub fn move(self: *Self, x: ?i32, y: ?i32) void {
    defer log.debug("<{*}> move to (x: {}, y: {})", .{ self, self.x, self.y });

    self.x = @max(
        config.border_width,
        @min(
            x orelse self.x,
            self.output.?.width-self.width-config.border_width
        )
    );
    self.y = @max(
        config.border_width,
        @min(
            y orelse self.y,
            self.output.?.height-self.height-config.border_width
        )
    );
}


pub fn snap_to(
    self: *Self,
    edge: river.WindowV1.Edges,
) void {
    var new_x: ?i32 = null;
    var new_y: ?i32 = null;

    if (edge.top) {
        new_y = 0;
    }
    if (edge.bottom) {
        new_y = self.output.?.height;
    }
    if (edge.left) {
        new_x = 0;
    }
    if (edge.right) {
        new_x = self.output.?.width;
    }

    self.move(new_x, new_y);
}


pub fn resize(self: *Self, width: ?i32, height: ?i32) void {
    defer log.debug(
        "<{*}> set dimensions to (width: {}, height: {})",
        .{ self, self.width, self.height },
    );

    self.width = @max(
        self.min_width,
        @min(
            width orelse self.width,
            self.output.?.width-self.x-config.border_width
        )
    );
    self.height = @max(
        self.min_height,
        @min(
            height orelse self.height,
            self.output.?.height-self.y-config.border_width
        )
    );
}


pub inline fn prepare_close(self: *Self) void {
    log.debug("<{*}> prepare to close", .{ self });

    self.rwm_window.close();
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
    if (output) |target_output| {
        log.debug("<{*}> prepare to fullscreen on {*}", .{ self, target_output });
    } else {
        log.debug("<{*}> prepare to fullscreen on window", .{ self });
    }


    self.append_event(.{ .fullscreen = output });
}


pub fn prepare_unfullscreen(self: *Self) void {
    log.debug("<{*}> prepare unfullscreen", .{ self });

    self.append_event(.unfullscreen);
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


pub fn is_visiable(self: *Self) bool {
    if (self.output) |output| {
        return (self.tag & output.tag) != 0;
    }
    return false;
}


pub fn is_visiable_in(self: *Self, output: *Output) bool {
    if (self.output == null) return false;

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


fn set_appid(self: *Self, app_id: ?[]const u8) void {
    if (self.app_id) |appid| {
        utils.allocator.free(appid);
        self.app_id = null;
    }
    if (app_id) |appid| {
        self.app_id = utils.allocator.dupe(u8, appid) catch return;
    }
}


fn set_title(self: *Self, title: ?[]const u8) void {
    if (self.title) |tt| {
        utils.allocator.free(tt);
        self.title = null;
    }
    if (title) |tt| {
        self.title = utils.allocator.dupe(u8, tt) catch return;
    }
}


fn center(self: *Self) void {
    self.x = @divFloor(self.output.?.width-self.width, 2);
    self.y = @divFloor(self.output.?.height-self.height, 2);
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

                self.width = @divFloor(self.output.?.width, 2);
                self.height = @divFloor(self.output.?.height, 2);
                self.center();
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

                std.debug.assert(self.fullscreen == .none);

                self.rwm_window.informFullscreen();
                if (data) |output| {
                    log.debug("<{*}> fullscreen on {*}", .{ self, output });

                    self.rwm_window.fullscreen(output.rwm_output);
                    self.fullscreen = .{ .output = output };

                    std.debug.assert(output.fullscreen_window == null);

                    output.fullscreen_window = self;
                } else {
                    log.debug("<{*}> fullscreen on window", .{ self });

                    self.fullscreen = .window;
                }
            },
            .unfullscreen => {
                log.debug("<{*}> managing unfullscreen", .{ self });

                switch (self.fullscreen) {
                    .none => unreachable,
                    .window => {
                        self.rwm_window.informNotFullscreen();
                    },
                    .output => |output| {
                        self.rwm_window.informNotFullscreen();
                        self.rwm_window.exitFullscreen();

                        std.debug.assert(output.fullscreen_window == self);

                        output.fullscreen_window = null;
                    }
                }
                self.fullscreen = .none;
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

            window.set_appid(mem.span(app_id));
        },
        .title => |data| {
            const title = data.title orelse return;

            log.debug("<{*}> title: {s}", .{ window, title });

            window.set_title(mem.span(title));
        },
        .closed => {
            log.debug("<{*}> closed", .{ window });

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

            // window.width = data.width;
            // window.height = data.height;
        },
        .dimensions_hint => |data| {
            log.debug(
                "<{*}> dimensions hint: (-width/+width: {}/{}, -height/+height: {}/{})",
                .{ window, data.min_width, data.max_width, data.min_height, data.max_height },
            );

            window.min_width = @max(window.min_width, data.min_width);
            window.min_height = @max(window.min_height, data.min_height);
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
            log.debug("<{*}> exit fullscreen requested", .{ window });

            window.prepare_unfullscreen();
        },
        .maximize_requested => {
            log.debug("<{*}> maximize requested", .{ window });

            window.prepare_maximize(true);
        },
        .unmaximize_requested => {
            log.debug("<{*}> unmaximize requested", .{ window });

            window.prepare_maximize(false);
        },
        .minimize_requested => {
            log.debug("<{*}> minimize requested", .{ window });
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
            log.debug("<{*}> pointer move requested: {*}", .{ window, data.seat });

            if (data.seat) |rwm_seat| {
                const seat: *Seat = @ptrCast(
                    @alignCast(river.SeatV1.getUserData(rwm_seat))
                );
                window.prepare_move(seat);
            }

        },
        .pointer_resize_requested => |data| {
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
        .unreliable_pid => |data| {
            log.debug("<{*}> unreliable pid: {}", .{ window, data.unreliable_pid });
        }
    }
}
