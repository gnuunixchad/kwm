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
const InputDevice = @import("input_device.zig");

var ctx: ?Self = null;


wl_compositor: *wl.Compositor,
wp_viewporter: *wp.Viewporter,
wp_single_pixel_buffer_manager: *wp.SinglePixelBufferManagerV1,
rwm: *river.WindowManagerV1,
rwm_xkb_bindings: *river.XkbBindingsV1,
rwm_layer_shell: *river.LayerShellV1,
rwm_input_manager: ?*river.InputManagerV1,

seats: wl.list.Head(Seat, .link) = undefined,
current_seat: ?*Seat = null,

outputs: wl.list.Head(Output, .link) = undefined,
current_output: ?*Output = null,

input_devices: wl.list.Head(InputDevice, .link) = undefined,

windows: wl.list.Head(Window, .link) = undefined,
focus_stack: wl.list.Head(Window, .flink) = undefined,

terminal_windows: std.AutoHashMap(i32, *Window) = undefined,

mode: config.Mode = .default,
running: bool = true,
env: process.EnvMap,
startup_processes: [config.startup_cmds.len]?process.Child = undefined,


pub fn init(
    wl_compositor: *wl.Compositor,
    wp_viewporter: *wp.Viewporter,
    wp_single_pixel_buffer_manager: *wp.SinglePixelBufferManagerV1,
    rwm: *river.WindowManagerV1,
    rwm_xkb_bindings: *river.XkbBindingsV1,
    rwm_layer_shell: *river.LayerShellV1,
    rwm_input_manager: *river.InputManagerV1,
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
        .rwm_input_manager = rwm_input_manager,
        .terminal_windows = .init(utils.allocator),
        .env = process.getEnvMap(utils.allocator) catch |err| blk: {
            log.warn("get EnvMap failed: {}", .{ err });
            break :blk .init(utils.allocator);
        },
    };
    ctx.?.seats.init();
    ctx.?.outputs.init();
    ctx.?.windows.init();
    ctx.?.input_devices.init();
    ctx.?.focus_stack.init();

    for (config.env) |pair| {
        const key, const value = pair;
        ctx.?.env.put(key, value) catch |err| {
            log.warn("put (key: {s}, value: {s}) to env map failed: {}", .{ key, value, err });
        };
    }

    for (0.., config.startup_cmds) |i, cmd| {
        ctx.?.startup_processes[i] = ctx.?.spawn(cmd);
    }

    rwm.setListener(*Self, rwm_listener, &ctx.?);
    rwm_input_manager.setListener(*Self, rwm_input_manager_listener, &ctx.?);
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
    if (ctx.?.rwm_input_manager) |rwm_input_manager| rwm_input_manager.destroy();

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
        var it = ctx.?.input_devices.safeIterator(.forward);
        while (it.next()) |input_device| {
            input_device.destroy();
        }
        ctx.?.input_devices.init();
    }

    {
        var it = ctx.?.windows.safeIterator(.forward);
        while (it.next()) |window| {
            window.destroy();
        }
        ctx.?.windows.init();
        ctx.?.focus_stack.init();
    }

    ctx.?.terminal_windows.deinit();

    ctx.?.env.deinit();

    for (&ctx.?.startup_processes) |*proc| {
        if (proc.*) |*child| {
            _ = child.kill() catch |err| {
                log.err("kill startup process {} failed: {}", .{ child.id, err });
                continue;
            };
            log.debug("kill startup process {}", .{ child.id });
        }
    }
}


pub inline fn get() *Self {
    std.debug.assert(ctx != null);

    return &ctx.?;
}


pub fn quit(self: *Self) void {
    log.debug("quit kwm", .{});

    self.running = false;
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
            if (window.is_visible_in(output)) {
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
            const new_window = switch (direction) {
                .forward => utils.cycle_list(Window, &self.windows.link, &win.link, .next),
                .reverse => utils.cycle_list(Window, &self.windows.link, &win.link, .prev),
            };
            defer win = new_window;
            if (new_window == window) break;
            if (new_window.is_visible_in(window.output.?)) {
                if (skip_floating and new_window.floating) continue;
                self.focus(new_window);
                break;
            }
        }
    }
}


pub fn focus_top_in(self: *Self, output: *Output, skip_floating: bool) ?*Window {
    var it = self.focus_stack.safeIterator(.forward);
    while (it.next()) |window| {
        if (window.is_visible_in(output)) {
            if (skip_floating and window.floating) continue;
            return window;
        }
    }
    return null;
}


pub fn focus_output_iter(self: *Self, direction: wl.list.Direction) void {
    log.debug("focus output iter: {s}", .{ @tagName(direction) });

    if (self.current_output) |output| {
        const new_output = switch (direction) {
            .forward => utils.cycle_list(Output, &self.outputs.link, &output.link, .next),
            .reverse => utils.cycle_list(Output, &self.outputs.link, &output.link, .prev),
        };
        if (new_output != output) {
            self.set_current_output(new_output);
        }
    }
}


pub fn send_to_output(self: *Self, window: *Window, direction: wl.list.Direction) void {
    log.debug("send {*} to {s} output", .{ window, @tagName(direction) });

    if (window.output) |output| {
        const new_output = switch (direction) {
            .forward => utils.cycle_list(Output, &self.outputs.link, &output.link, .next),
            .reverse => utils.cycle_list(Output, &self.outputs.link, &output.link, .prev),
        };
        if (new_output != output) {
            window.set_output(new_output);
        }
    }
}


pub inline fn focus_exclusive(self: *Self) bool {
    return if (self.current_seat) |seat| seat.focus_exclusive else false;
}


pub fn swap(self: *Self, direction: wl.list.Direction) void {
    log.debug("swap window: {s}", .{ @tagName(direction) });

    if (self.focused_window()) |window| {
        if (window.floating) return;

        var win = window;
        while (true) {
            const new_window = switch (direction) {
                .forward => utils.cycle_list(Window, &self.windows.link, &win.link, .next),
                .reverse => utils.cycle_list(Window, &self.windows.link, &win.link, .prev),
            };
            defer win = new_window;
            if (new_window == window) break;
            if (new_window.is_visible_in(window.output.?) and !new_window.floating) {
                window.link.swapWith(&new_window.link);
                self.focus(window);
                break;
            }
        }
    }
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


pub inline fn switch_mode(self: *Self, mode: config.Mode) void {
    log.debug("switch mode from {s} to {s}", .{ @tagName(self.mode), @tagName(mode) });

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


pub fn register_terminal(self: *Self, window: *Window) void {
    log.debug("register terminal window {*}(pid: {})", .{ window, window.pid });

    self.terminal_windows.put(window.pid, window) catch |err| {
        log.err("put (key: {}, value: {*}) failed: {}", .{ window.pid, window, err });
        return;
    };
}


pub fn unregister_terminal(self: *Self, window: *Window) void {
    log.debug("unregister terminal window {*}(pid: {})", .{ window, window.pid });

    if (!self.terminal_windows.remove(window.pid)) {
        log.debug("remove pid {} failed, not found", .{ window.pid });
    }
}


pub inline fn find_terminal(self: *Self, pid: i32) ?*Window {
    return self.terminal_windows.get(pid);
}


pub inline fn set_current_output(self: *Self, output: ?*Output) void {
    log.debug("set current output: {*}", .{ output });

    self.current_output = output;

    if (self.current_output) |current_output| {
        if (current_output.rwm_layer_shell_output) |rwm_layer_shell_output| {
            rwm_layer_shell_output.setDefault();
        }
    }
}


pub inline fn set_current_seat(self: *Self, seat: ?*Seat) void {
    log.debug("set current seat: {*}", .{ seat });

    self.current_seat = seat;
}


pub fn spawn(self: *Self, argv: []const []const u8) ?process.Child {
    if (builtins.mode == .Debug) {
        const cmd = mem.join(utils.allocator, " ", argv) catch |err| {
            log.err("join failed: {}", .{ err });
            return null;
        };
        defer utils.allocator.free(cmd);

        log.debug("spawn: `{s}`", .{ cmd });
    }

    var child = process.Child.init(argv, utils.allocator);
    child.pgid = 0;
    child.env_map = &self.env;
    child.cwd = switch (config.working_directory) {
        .none => null,
        .home => self.env.get("HOME"),
        .custom => |dir| dir,
    };
    child.spawn() catch |err| {
        log.err("spawn failed: {}", .{ err });
        return null;
    };
    return child;
}


pub inline fn spawn_shell(self: *Self, cmd: []const u8) ?process.Child {
    return self.spawn(&[_][]const u8 { "sh", "-c", cmd });
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

    const cache = struct {
        pub var mode: config.Mode = undefined;
    };

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
                    if (output.fullscreen_window) |window| {
                        if (window.is_visible_in(output)) {
                            continue;
                        }
                    }
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
                    if (!window.is_visible() or window.is_under_fullscreen_window()) {
                        window.hide();
                    }

                    window.set_border(
                        if (window.fullscreen == .output) 0 else config.border_width,
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

            cache.mode = context.mode;
            context.switch_mode(.lock);
        },
        .session_unlocked => {
            log.debug("session unlocked", .{});

            context.switch_mode(cache.mode);
        }
    }
}


fn rwm_input_manager_listener(rwm_input_manager: *river.InputManagerV1, event: river.InputManagerV1.Event, context: *Self) void {
    std.debug.assert(rwm_input_manager == context.rwm_input_manager.?);

    switch (event) {
        .input_device => |data| {
            log.debug("new input_device {*}", .{ data.id });

            const input_device = InputDevice.create(data.id) catch |err| {
                log.err("create input device failed: {}", .{ err });
                return;
            };

            context.input_devices.append(input_device);
        },
        .finished => {
            log.debug("{*} finished", .{ rwm_input_manager });

            rwm_input_manager.destroy();
            context.rwm_input_manager = null;
        }
    }
}
