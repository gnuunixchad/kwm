const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;

const utils = @import("utils");
const kwm = @import("kwm");

const Globals = struct {
    wl_compositor: ?*wl.Compositor = null,
    wp_viewporter: ?*wp.Viewporter = null,
    wp_single_pixel_buffer_manager: ?*wp.SinglePixelBufferManagerV1 = null,
    rwm: ?*river.WindowManagerV1 = null,
    rwm_xkb_bindings: ?*river.XkbBindingsV1 = null,
    rwm_layer_shell: ?*river.LayerShellV1 = null,
    rwm_input_manager: ?*river.InputManagerV1 = null,
    rwm_libinput_config: ?*river.LibinputConfigV1 = null,
};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer if (gpa.deinit() != .ok) @panic("memory leak");
    utils.init_allocator(&gpa.allocator());

    const display = try wl.Display.connect(null);
    defer display.disconnect();

    {
        const registry = display.getRegistry() catch return error.GetRegistryFailed;

        var globals: Globals = .{};
        registry.setListener(*Globals, registry_listener, &globals);

        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        const wl_compositor = globals.wl_compositor orelse return error.MissingCompositor;
        const wp_single_pixel_buffer_manager = globals.wp_single_pixel_buffer_manager orelse return error.MissingSinglePixelBufferManagerV1;
        const wp_viewporter = globals.wp_viewporter orelse return error.MissingViewporter;
        const rwm = globals.rwm orelse return error.MissingRiverWindowManagerV1;
        const rwm_xkb_bindings = globals.rwm_xkb_bindings orelse return error.MissingRiverXkbBindingsV1;
        const rwm_layer_shell = globals.rwm_layer_shell orelse return error.MissingRiverLayerShellV1;
        const rwm_input_manager = globals.rwm_input_manager orelse return error.MissingRiverInputManager;
        const rwm_libinput_config = globals.rwm_libinput_config orelse return error.MissingRiverLibinputConfig;

        kwm.Context.init(
            registry,
            wl_compositor,
            wp_viewporter,
            wp_single_pixel_buffer_manager,
            rwm,
            rwm_xkb_bindings,
            rwm_layer_shell,
            rwm_input_manager,
            rwm_libinput_config,
        );
    }
    defer kwm.Context.deinit();

    const wayland_fd = display.getFd();

    var mask = posix.sigemptyset();
    posix.sigaddset(&mask, posix.SIG.INT);
    posix.sigaddset(&mask, posix.SIG.TERM);
    posix.sigaddset(&mask, posix.SIG.QUIT);
    posix.sigaddset(&mask, posix.SIG.CHLD);
    posix.sigprocmask(posix.SIG.BLOCK, &mask, null);
    const signal_fd = try posix.signalfd(-1, &mask, 1 << @bitOffsetOf(posix.O, "NONBLOCK"));

    var poll_fds = [_]posix.pollfd {
        .{ .fd = wayland_fd, .events = posix.POLL.IN, .revents = 0 },
        .{ .fd = signal_fd, .events = posix.POLL.IN, .revents = 0 },
    };

    const context = kwm.Context.get();
    while (context.running) {
        _ = display.flush();
        _ = try posix.poll(&poll_fds, -1);

        if (poll_fds[0].revents & posix.POLL.IN != 0) {
            if (display.dispatch() != .SUCCESS) {
                return error.DispatchFailed;
            }
        }

        if (poll_fds[1].revents & posix.POLL.IN != 0) {
            var signal_info: posix.siginfo_t = undefined;
            const buffer: *[@sizeOf(posix.siginfo_t)]u8 = @ptrCast(&signal_info);
            const nbytes = posix.read(signal_fd, buffer) catch |err| {
                switch (err) {
                    error.WouldBlock => continue,
                    else => return err,
                }
            };
            if (nbytes != @sizeOf(posix.siginfo_t)) continue;

            context.handle_signal(signal_info.signo);
        }
    }
}


fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                globals.wl_compositor = registry.bind(global.name, wl.Compositor, 4) catch return;
            } else if (mem.orderZ(u8, global.interface, wp.Viewporter.interface.name) == .eq) {
                globals.wp_viewporter = registry.bind(global.name, wp.Viewporter, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wp.SinglePixelBufferManagerV1.interface.name) == .eq) {
                globals.wp_single_pixel_buffer_manager = registry.bind(global.name, wp.SinglePixelBufferManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.WindowManagerV1.interface.name) == .eq) {
                globals.rwm = registry.bind(global.name, river.WindowManagerV1, 2) catch return;
            } else if (mem.orderZ(u8, global.interface, river.XkbBindingsV1.interface.name) == .eq) {
                globals.rwm_xkb_bindings = registry.bind(global.name, river.XkbBindingsV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.LayerShellV1.interface.name) == .eq) {
                globals.rwm_layer_shell = registry.bind(global.name, river.LayerShellV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.InputManagerV1.interface.name) == .eq) {
                globals.rwm_input_manager = registry.bind(global.name, river.InputManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.LibinputConfigV1.interface.name) == .eq) {
                globals.rwm_libinput_config = registry.bind(global.name, river.LibinputConfigV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}
