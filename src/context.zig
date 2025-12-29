const Self = @This();

const builtins = @import("builtin");
const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const process = std.process;
const log = std.log.scoped(.context);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;

const utils = @import("utils.zig");
const config = @import("config.zig");
const Seat = @import("seat.zig");
const Output = @import("output.zig");
const Window = @import("window.zig");

var ctx: ?Self = null;


wl_compositor: *wl.Compositor,
wp_viewporter: *wp.Viewporter,
wp_single_pixel_buffer_manager: *wp.SinglePixelBufferManagerV1,
rwm: *river.WindowManagerV1,
rwm_xkb_bindings: *river.XkbBindingsV1,
rwm_layer_shell: *river.LayerShellV1,

seats: wl.list.Head(Seat, .link) = undefined,
current_seat: ?*Seat = null,

outputs: wl.list.Head(Output, .link) = undefined,
current_output: ?*Output = null,

windows: wl.list.Head(Window, .link) = undefined,
focus_stack: wl.list.Head(Window, .flink) = undefined,

mode: config.Mode = .default,
running: bool = true,
locked: bool = false,
env: process.EnvMap,


pub fn init(
    wl_compositor: *wl.Compositor,
    wp_viewporter: *wp.Viewporter,
    wp_single_pixel_buffer_manager: *wp.SinglePixelBufferManagerV1,
    rwm: *river.WindowManagerV1,
    rwm_xkb_bindings: *river.XkbBindingsV1,
    rwm_layer_shell: *river.LayerShellV1
) void {
    // initialize once
    if (ctx != null) return;

    log.info("init context", .{});

    ctx = .{
        .wl_compositor = wl_compositor,
        .wp_viewporter = wp_viewporter,
        .wp_single_pixel_buffer_manager = wp_single_pixel_buffer_manager,
        .rwm = rwm,
        .rwm_xkb_bindings = rwm_xkb_bindings,
        .rwm_layer_shell = rwm_layer_shell,
        .env = process.getEnvMap(utils.allocator) catch |err| blk: {
            log.warn("get EnvMap failed: {}", .{ err });
            break :blk .init(utils.allocator);
        },
    };
    ctx.?.seats.init();
    ctx.?.outputs.init();
    ctx.?.windows.init();
    ctx.?.focus_stack.init();

    rwm.setListener(*Self, rwm_listener, &ctx.?);
}


pub fn deinit() void {
    std.debug.assert(ctx != null);

    log.info("deinit context", .{});

    defer ctx = null;

    ctx.?.wl_compositor.destroy();
    ctx.?.wp_viewporter.destroy();
    ctx.?.wp_single_pixel_buffer_manager.destroy();
    ctx.?.rwm.destroy();
    ctx.?.rwm_xkb_bindings.destroy();
    ctx.?.rwm_layer_shell.destroy();

    {
        var it = ctx.?.seats.safeIterator(.forward);
        while (it.next()) |seat| {
            seat.destroy();
        }
        ctx.?.seats.init();
    }
    ctx.?.current_seat = null;

    {
        var it = ctx.?.outputs.safeIterator(.forward);
        while (it.next()) |output| {
            output.destroy();
        }
        ctx.?.outputs.init();
    }
    ctx.?.current_output = null;

    {
        var it = ctx.?.windows.safeIterator(.forward);
        while (it.next()) |window| {
            window.destroy();
        }
        ctx.?.windows.init();
        ctx.?.focus_stack.init();
    }

    ctx.?.env.deinit();
}


pub inline fn get() *Self {
    std.debug.assert(ctx != null);

    return &ctx.?;
}


pub fn focus(self: *Self, window: *Window) void {
    log.debug("<{*}> focus window: {*}", .{ self, window });

    window.flink.remove();
    self.focus_stack.prepend(window);
}


pub fn focused_window(self: *Self) ?*Window {
    if (self.current_output) |output| {
        var it = self.focus_stack.safeIterator(.forward);
        while (it.next()) |window| {
            if (window.is_visiable_in(output)) {
                return window;
            }
        }
    }
    return null;
}


pub fn focus_iter(self: *Self, direction: wl.list.Direction, skip_floating: bool) void {
    log.debug("focus iter: {s}", .{ @tagName(direction) });

    if (self.focused_window()) |window| {
        var win = window;
        while (true) {
            const new_win = switch (direction) {
                .forward => utils.cycle_list(Window, &self.windows.link, &win.link, .next),
                .reverse => utils.cycle_list(Window, &self.windows.link, &win.link, .prev),
            };
            defer win = new_win;
            if (new_win == win) break;
            if (new_win.is_visiable_in(window.output.?)) {
                if (skip_floating and new_win.floating) continue;
                self.focus(new_win);
                break;
            }
        }
    }
}


pub fn focus_top_in(self: *Self, output: *Output, skip_floating: bool) ?*Window {
    var it = self.focus_stack.safeIterator(.forward);
    while (it.next()) |window| {
        if (window.is_visiable_in(output)) {
            if (skip_floating and window.floating) continue;
            return window;
        }
    }
    return null;
}


pub inline fn focus_exclusive(self: *Self) bool {
    return if (self.current_seat) |seat| seat.focus_exclusive else false;
}


pub fn prepare_remove_output(self: *Self, output: *Output) void {
    log.debug("prepare to remove output {*}", .{ output });

    if (output == self.current_output) {
        self.promote_new_output();
    }

    const new_output = self.current_output;
    {
        var it = self.windows.iterator(.forward);
        while (it.next()) |window| {
            if (window.output == output) {
                window.set_former_output(output.name);
                window.set_output(new_output);
            }
        }
    }
}


pub fn prepare_remove_seat(self: *Self, seat: *Seat) void {
    log.debug("prepare to remove seat {*}", .{ seat });

    if (seat == self.current_seat) {
        self.promote_new_seat();
    }
}


pub fn switch_mode(self: *Self, mode: config.Mode) void {
    log.debug("switch mode from {s} to {s}", .{ @tagName(self.mode), @tagName(mode) });

    {
        var it = self.seats.safeIterator(.forward);
        while (it.next()) |seat| {
            seat.toggle_bindings(self.mode, false);
            seat.toggle_bindings(mode, true);
        }
    }
    self.mode = mode;
}


pub fn shift_to_head(self: *Self, window: *Window) void {
    log.debug("shift window {*} to head", .{ window });

    window.link.remove();
    self.windows.prepend(window);
}


pub fn toggle_fullscreen(self: *Self, in_window: bool) void {
    if (self.current_output) |output| {
        if (output.fullscreen_window) |window| {
            window.prepare_unfullscreen();
        } else {
            if (self.focused_window()) |window| {
                switch (window.fullscreen) {
                    .none => window.prepare_fullscreen(if (in_window) null else window.output.?),
                    else => window.prepare_unfullscreen(),
                }
            }
        }
    }
}


pub inline fn set_current_output(self: *Self, output: ?*Output) void {
    log.debug("set current output: {*}", .{ output });

    self.current_output = output;
}


pub inline fn set_current_seat(self: *Self, seat: ?*Seat) void {
    log.debug("set current seat: {*}", .{ seat });

    self.current_seat = seat;
}


pub fn spawn(self: *Self, argv: []const []const u8) void {
    if (builtins.mode == .Debug) {
        const cmd = mem.join(utils.allocator, " ", argv) catch |err| {
            log.err("join failed: {}", .{ err });
            return;
        };
        defer utils.allocator.free(cmd);

        log.debug("spawn: `{s}`", .{ cmd });
    }

    var child = process.Child.init(argv, utils.allocator);
    child.env_map = &self.env;
    child.spawn() catch |err| {
        log.err("spawn failed: {}", .{ err });
        return;
    };
}


pub inline fn spawn_shell(self: *Self, cmd: []const u8) void {
    self.spawn(&[_][]const u8 { "sh", "-c", cmd });
}


fn promote_new_output(self: *Self) void {
    log.debug("promote new output", .{});

    const former_output = self.current_output.?;
    const current_output = utils.cycle_list(
        Output,
        &self.outputs.link,
        &former_output.link,
        .prev,
    );

    self.set_current_output(
        if (current_output == former_output) null
        else current_output
    );
}


fn promote_new_seat(self: *Self) void {
    log.debug("promote new seat", .{});

    const former_seat = self.current_seat.?;
    const current_seat = utils.cycle_list(
        Seat,
        &self.seats.link,
        &former_seat.link,
        .prev,
    );

    self.set_current_seat(
        if (current_seat == former_seat) null
        else current_seat
    );
}


fn prepare_manage(self: *Self) void {
    log.debug("prepare to manage", .{});

    {
        var it = self.seats.safeIterator(.forward);
        while (it.next()) |seat| {
            seat.manage();
        }
    }

    {
        var it = self.windows.safeIterator(.forward);
        while (it.next()) |window| {
            window.handle_events();
        }
    }
}


fn rwm_listener(rwm: *river.WindowManagerV1, event: river.WindowManagerV1.Event, context: *Self) void {
    std.debug.assert(rwm == context.rwm);

    switch (event) {
        .finished => {
            log.debug("window manager finished", .{});

            context.running = false;
        },
        .unavailable => @panic("another window manager is already running"),
        .manage_start => {
            log.debug("manage start", .{});

            context.prepare_manage();

            {
                var it = context.outputs.safeIterator(.forward);
                while (it.next()) |output| {
                    output.manage();
                }
            }

            {
                var it = context.windows.safeIterator(.forward);
                while (it.next()) |window| {
                    window.manage();
                }
            }

            {
                var it = context.seats.iterator(.forward);
                while (it.next()) |seat| {
                    seat.try_focus();
                }
            }

            rwm.manageFinish();
        },
        .render_start => {
            log.debug("render start", .{});

            const focused = context.focused_window();
            {
                var it = context.windows.safeIterator(.forward);
                while (it.next()) |window| {
                    if (!window.is_visiable()) {
                        window.hide();
                    }

                    window.set_border(
                        config.border_width,
                        if (!context.focus_exclusive() and window == focused)
                            config.border_color.focus
                        else config.border_color.unfocus
                    );
                    window.render();
                }
            }

            if (focused) |window| {
                // move focus to head of focus_stack
                context.focus(window);

                // place focused window top
                window.place(.top);
            }

            rwm.renderFinish();
        },
        .window => |data| {
            log.debug("new window {*}", .{ data.id });

            const window = Window.create(data.id) catch |err| {
                log.err("create window failed: {}", .{ err });
                return;
            };

            if (context.current_output) |output| {
                window.set_tag(output.tag);
                window.set_output(output);
            }

            context.windows.prepend(window);
            context.focus(window);
        },
        .output => |data| {
            log.debug("new output {*}", .{ data.id });

            const rwm_layer_shell_output = context.rwm_layer_shell.getOutput(data.id) catch null;
            const output = Output.create(data.id, rwm_layer_shell_output) catch |err| {
                log.err("create output failed: {}", .{ err });
                return;
            };
            context.outputs.append(output);

            if (context.current_output == null) {
                context.current_output = output;
            }
        },
        .seat => |data| {
            log.debug("new seat {*}", .{ data.id });

            const seat = Seat.create(data.id) catch |err| {
                log.err("create seat failed: {}", .{ err });
                return;
            };
            context.seats.append(seat);

            if (context.current_seat == null) {
                context.current_seat = seat;
            }
        },
        .session_locked => {
            log.debug("session locked", .{});

            context.locked = true;
        },
        .session_unlocked => {
            log.debug("session unlocked", .{});

            context.locked = false;
        }
    }
}
