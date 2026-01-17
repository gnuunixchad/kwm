const Self = @This();

const build_options = @import("build_options");
const builtins = @import("builtin");
const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;
const process = std.process;
const log = std.log.scoped(.context);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;

const utils = @import("utils");
const config = @import("config");

const types = @import("types.zig");
const Seat = @import("seat.zig");
const Output = @import("output.zig");
const Window = @import("window.zig");
const InputDevice = @import("input_device.zig");
const LibinputDevice = @import("libinput_device.zig");

var ctx: ?Self = null;


wl_registry: *wl.Registry,
wl_compositor: *wl.Compositor,
wl_subcompositor: *wl.Subcompositor,
wl_shm: *wl.Shm,
wp_viewporter: *wp.Viewporter,
wp_single_pixel_buffer_manager: *wp.SinglePixelBufferManagerV1,
rwm: *river.WindowManagerV1,
rwm_xkb_bindings: *river.XkbBindingsV1,
rwm_layer_shell: *river.LayerShellV1,
rwm_input_manager: ?*river.InputManagerV1,
rwm_libinput_config: ?*river.LibinputConfigV1,

seats: wl.list.Head(Seat, .link) = undefined,
current_seat: ?*Seat = null,

outputs: wl.list.Head(Output, .link) = undefined,
current_output: ?*Output = null,

input_devices: wl.list.Head(InputDevice, .link) = undefined,
libinput_devices: wl.list.Head(LibinputDevice, .link) = undefined,

windows: wl.list.Head(Window, .link) = undefined,
focus_stack: wl.list.Head(Window, .flink) = undefined,

bar_status_fd: ?posix.fd_t = null,

terminal_windows: std.AutoHashMap(i32, *Window) = undefined,

mode: config.Mode = .default,
running: bool = true,
env: process.EnvMap,
startup_processes: [config.startup_cmds.len]?process.Child = undefined,


pub fn init(
    wl_registry: *wl.Registry,
    wl_compositor: *wl.Compositor,
    wl_subcompositor: *wl.Subcompositor,
    wl_shm: *wl.Shm,
    wp_viewporter: *wp.Viewporter,
    wp_single_pixel_buffer_manager: *wp.SinglePixelBufferManagerV1,
    rwm: *river.WindowManagerV1,
    rwm_xkb_bindings: *river.XkbBindingsV1,
    rwm_layer_shell: *river.LayerShellV1,
    rwm_input_manager: *river.InputManagerV1,
    rwm_libinput_config: *river.LibinputConfigV1,
) void {
    // initialize once
    if (ctx != null) return;

    if (comptime build_options.bar_enabled) {
        _ = @import("fcft").init(.auto, false, .err);
    }

    log.info("init context", .{});

    ctx = .{
        .wl_registry = wl_registry,
        .wl_compositor = wl_compositor,
        .wl_subcompositor = wl_subcompositor,
        .wl_shm = wl_shm,
        .wp_viewporter = wp_viewporter,
        .wp_single_pixel_buffer_manager = wp_single_pixel_buffer_manager,
        .rwm = rwm,
        .rwm_xkb_bindings = rwm_xkb_bindings,
        .rwm_layer_shell = rwm_layer_shell,
        .rwm_input_manager = rwm_input_manager,
        .rwm_libinput_config = rwm_libinput_config,
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
    ctx.?.libinput_devices.init();
    ctx.?.focus_stack.init();

    for (config.env) |pair| {
        const key, const value = pair;
        ctx.?.env.put(key, value) catch |err| {
            log.warn("put (key: {s}, value: {s}) to env map failed: {}", .{ key, value, err });
        };
    }

    if (config.xcursor_theme) |xcursor_theme| {
        ctx.?.env.put("XCURSOR_THEME", xcursor_theme.name) catch |err| {
            log.warn("put XCURSOR_THEME to `{s}` failed: {}", .{ xcursor_theme.name, err });
        };
        ctx.?.env.put("XCURSOR_SIZE", fmt.comptimePrint("{}", .{ xcursor_theme.size })) catch |err| {
            log.warn("put XCURSOR_SIZE to `{}` failed: {}", .{ xcursor_theme.size, err });
        };
    }

    for (0.., config.startup_cmds) |i, cmd| {
        ctx.?.startup_processes[i] = ctx.?.spawn(cmd);
    }

    rwm.setListener(*Self, rwm_listener, &ctx.?);
    rwm_input_manager.setListener(*Self, rwm_input_manager_listener, &ctx.?);
    rwm_libinput_config.setListener(*Self, rwm_libinput_config_listener, &ctx.?);
}


pub fn deinit() void {
    std.debug.assert(ctx != null);

    log.info("deinit context", .{});

    if (comptime build_options.bar_enabled) {
        @import("fcft").fini();
    }

    defer ctx = null;

    ctx.?.wl_registry.destroy();
    ctx.?.wl_compositor.destroy();
    ctx.?.wl_subcompositor.destroy();
    ctx.?.wl_shm.destroy();
    ctx.?.wp_viewporter.destroy();
    ctx.?.wp_single_pixel_buffer_manager.destroy();
    ctx.?.rwm.destroy();
    ctx.?.rwm_xkb_bindings.destroy();
    ctx.?.rwm_layer_shell.destroy();
    if (ctx.?.rwm_input_manager) |rwm_input_manager| rwm_input_manager.destroy();
    if (ctx.?.rwm_libinput_config) |rwm_libinput_config| rwm_libinput_config.destroy();

    // first destroy windows for it's destroy function may depends on others
    {
        var it = ctx.?.windows.safeIterator(.forward);
        while (it.next()) |window| {
            window.destroy();
        }
        ctx.?.windows.init();
        ctx.?.focus_stack.init();
    }

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
        var it = ctx.?.libinput_devices.safeIterator(.forward);
        while (it.next()) |libinput_device| {
            libinput_device.destroy();
        }
        ctx.?.libinput_devices.init();
    }

    if (ctx.?.is_listening_status()) {
        ctx.?.stop_listening_status();
    }

    ctx.?.terminal_windows.deinit();

    ctx.?.env.deinit();

    for (&ctx.?.startup_processes) |*proc| {
        if (proc.*) |*child| {
            posix.kill(child.id, posix.SIG.TERM) catch |err| {
                log.err("kill startup process {} failed: {}", .{ child.id, err });
                continue;
            };
            log.debug("kill startup process {}", .{ child.id });
        }
    }
}


pub fn start_listening_status(self: *Self) void {
    self.stop_listening_status();

    self.bar_status_fd = switch (config.bar.status) {
        .text => null,
        .stdin => blk: {
            var flags = posix.fcntl(posix.STDIN_FILENO, posix.F.GETFL, 0) catch |err| {
                log.err("get fd flags failed: {}", .{ err });
                break :blk null;
            };
            flags |= 1 << @bitOffsetOf(posix.O, "NONBLOCK");

            _ = posix.fcntl(posix.STDIN_FILENO, posix.F.SETFL, flags) catch |err| {
                log.err("set stdin fd NONBLOCK failed: {}", .{ err });
                break :blk null;
            };

            break :blk posix.STDIN_FILENO;
        },
        .fifo => |fifo| try_open_fifo(fifo) catch null,
    };
}


pub fn stop_listening_status(self: *Self) void {
    switch (config.bar.status) {
        .text => {},
        .stdin => self.bar_status_fd = null,
        .fifo => if (self.bar_status_fd) |fd| {
            log.debug("close fd {}`", .{ fd });
            posix.close(fd);
            self.bar_status_fd = null;
        }
    }
}


pub inline fn is_listening_status(self: *Self) bool {
    return self.bar_status_fd != null;
}


pub fn update_bar_status(self: *Self) void {
    if (comptime build_options.bar_enabled) {
        if (self.bar_status_fd) |fd| {
            log.debug("update status", .{});

            const dest_buf = &@import("bar.zig").status_buffer;
            const nbytes = posix.read(fd, dest_buf) catch |err| {
                switch (err) {
                    error.WouldBlock => log.debug("no data in fd {}", .{ fd }),
                    else => log.err("read data from fd {} failed: {}", .{ fd, err }),
                }
                return;
            };

            log.debug("read {} bytes data from fd {}", .{ nbytes, fd });

            if (nbytes > 0) {
                var show_bar_num: u8 = 0;
                var it = self.outputs.safeIterator(.forward);
                while (it.next()) |output| {
                    output.bar.damage(.status);

                    if (!output.bar.hided) {
                        show_bar_num += 1;
                    }
                }

                if (show_bar_num > 0) self.rwm.manageDirty();
            } else {
                self.stop_listening_status();
            }
        } else {
            log.warn("call `update_bar_status` while bar_status_fd is null", .{});
        }
    } else unreachable;
}


pub inline fn get() *Self {
    std.debug.assert(ctx != null);

    return &ctx.?;
}


pub fn handle_signal(self: *Self, sig: i32) void {
    switch (sig) {
        posix.SIG.INT, posix.SIG.TERM, posix.SIG.QUIT => self.quit(),
        posix.SIG.CHLD => {
            while (true) {
                const res = utils.waitpid(-1, posix.W.NOHANG) catch |err| {
                    log.warn("wait failed: {}", .{ err });
                    break;
                };
                if (res.pid <= 0) break;
                log.debug("wait pid {}", .{ res.pid });
            }
        },
        else => {}
    }
}


pub fn state(self: *Self) types.State {
    const layout =
        if (self.current_output) |output|
            output.current_layout()
        else null;
    return .{
        .layout = layout,
    };
}


pub fn quit(self: *Self) void {
    log.debug("quit kwm", .{});

    self.running = false;
}


pub fn focus(self: *Self, window: *Window) void {
    log.debug("<{*}> focus window: {*}", .{ self, window });

    if (window.output) |output| {
        self.set_current_output(output);
    }

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


pub fn focus_iter(self: *Self, direction: types.Direction, skip_floating: bool) void {
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


pub fn focus_output_iter(self: *Self, direction: types.Direction) void {
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


pub fn send_to_output(self: *Self, window: *Window, direction: types.Direction) void {
    log.debug("send {*} to {s} output", .{ window, @tagName(direction) });

    if (window.output) |output| {
        const new_output = switch (direction) {
            .forward => utils.cycle_list(Output, &self.outputs.link, &output.link, .next),
            .reverse => utils.cycle_list(Output, &self.outputs.link, &output.link, .prev),
        };
        if (new_output != output) {
            window.set_output(new_output, true);
        }
    }
}


pub inline fn focus_exclusive(self: *Self) bool {
    return if (self.current_seat) |seat| seat.focus_exclusive else false;
}


pub fn swap(self: *Self, direction: types.Direction) void {
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
                window.set_output(new_output, false);
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

    if (comptime build_options.bar_enabled) {
        var it = self.outputs.safeIterator(.forward);
        while (it.next()) |output| {
            output.bar.damage(.mode);
        }
    }
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

    if (comptime build_options.bar_enabled) {
        if (self.current_output) |o| o.bar.damage(.title);
    }

    if (self.current_output != output) {
        self.current_output = output;

        if (output) |o| {
            if (comptime build_options.bar_enabled) o.bar.damage(.title);

            if (o.rwm_layer_shell_output) |rwm_layer_shell_output| {
                rwm_layer_shell_output.setDefault();
            }
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
        .unavailable => {
            log.err("another window manager is already running", .{});

            context.running = false;
        },
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

            if (comptime build_options.bar_enabled) {
                {
                    var it = context.outputs.safeIterator(.forward);
                    while (it.next()) |output| {
                        output.bar.render();
                    }
                }
            }

            rwm.renderFinish();
        },
        .window => |data| {
            log.debug("new window {*}", .{ data.id });

            const window = Window.create(data.id, context.current_output) catch |err| {
                log.err("create window failed: {}", .{ err });
                return;
            };

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
                context.set_current_output(output);
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
                context.set_current_seat(seat);
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


fn rwm_libinput_config_listener(rwm_libinput_config: *river.LibinputConfigV1, event: river.LibinputConfigV1.Event, context: *Self) void {
    std.debug.assert(rwm_libinput_config == context.rwm_libinput_config);

    switch (event) {
        .libinput_device => |data| {
            log.debug("new libinput_device {*}", .{ data.id });

            const libinput_device = LibinputDevice.create(data.id) catch |err| {
                log.err("create libinput device failed: {}", .{ err });
                return;
            };

            context.libinput_devices.append(libinput_device);
        },
        .finished => {
            log.debug("{*} finished", .{ rwm_libinput_config });

            rwm_libinput_config.destroy();
            context.rwm_libinput_config = null;
        }
    }
}


fn try_open_fifo(fifo: []const u8) !posix.fd_t {
    log.debug("try open fifo file `{s}`", .{ fifo });

    const fd = posix.open(fifo, .{ .ACCMODE = .RDWR, .NONBLOCK = true }, 0) catch |err| {
        log.warn("open `{s}` failed: {}", .{ fifo, err });
        return error.OpenFailed;
    };
    errdefer posix.close(fd);

    const stat = posix.fstat(fd) catch |err| {
        log.warn("stat `{s}` failed: {}", .{ fifo, err });
        return error.StatFailed;
    };

    if (stat.mode & posix.S.IFMT == 0) {
        log.warn("`{s}` is not a fifo file", .{ fifo });
        return error.NotFifo;
    }
    return fd;
}
