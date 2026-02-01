const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;

const kwm = @import("kwm");

const Globals = struct {
    wl_compositor: ?*wl.Compositor = null,
    wl_subcompositor: ?*wl.Subcompositor = null,
    wl_shm: ?*wl.Shm = null,
    wp_viewporter: ?*wp.Viewporter = null,
    wp_fractional_scale_manager: ?*wp.FractionalScaleManagerV1 = null,
    wp_single_pixel_buffer_manager: ?*wp.SinglePixelBufferManagerV1 = null,
    rwm: ?*river.WindowManagerV1 = null,
    rwm_xkb_bindings: ?*river.XkbBindingsV1 = null,
    rwm_layer_shell: ?*river.LayerShellV1 = null,
    rwm_input_manager: ?*river.InputManagerV1 = null,
    rwm_libinput_config: ?*river.LibinputConfigV1 = null,
    rwm_xkb_config: ?*river.XkbConfigV1 = null,
};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer if (gpa.deinit() != .ok) @panic("memory leak");
    kwm.init_allocator(&gpa.allocator());

    const display = try wl.Display.connect(null);
    defer display.disconnect();

    {
        const registry = display.getRegistry() catch return error.GetRegistryFailed;

        var globals: Globals = .{};
        registry.setListener(*Globals, registry_listener, &globals);

        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        const wl_compositor = globals.wl_compositor orelse return error.MissingCompositor;
        const wl_subcompositor = globals.wl_subcompositor orelse return error.MissingSubcompositor;
        const wl_shm = globals.wl_shm orelse return error.MissingShm;
        const wp_fractional_scale_manager = globals.wp_fractional_scale_manager orelse return error.MissingFractionalScaleManagerV1;
        const wp_single_pixel_buffer_manager = globals.wp_single_pixel_buffer_manager orelse return error.MissingSinglePixelBufferManagerV1;
        const wp_viewporter = globals.wp_viewporter orelse return error.MissingViewporter;
        const rwm = globals.rwm orelse return error.MissingRiverWindowManagerV1;
        const rwm_xkb_bindings = globals.rwm_xkb_bindings orelse return error.MissingRiverXkbBindingsV1;
        const rwm_layer_shell = globals.rwm_layer_shell orelse return error.MissingRiverLayerShellV1;
        const rwm_input_manager = globals.rwm_input_manager orelse return error.MissingRiverInputManager;
        const rwm_libinput_config = globals.rwm_libinput_config orelse return error.MissingRiverLibinputConfig;
        const rwm_xkb_config = globals.rwm_xkb_config orelse return error.MissingRiverXkbConfig;

        kwm.init(
            registry,
            wl_compositor,
            wl_subcompositor,
            wl_shm,
            wp_viewporter,
            wp_fractional_scale_manager,
            wp_single_pixel_buffer_manager,
            rwm,
            rwm_xkb_bindings,
            rwm_layer_shell,
            rwm_input_manager,
            rwm_libinput_config,
            rwm_xkb_config,
        );
    }
    defer kwm.deinit();
    try kwm.run(display);
}


fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                globals.wl_compositor = registry.bind(global.name, wl.Compositor, 4) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Subcompositor.interface.name) == .eq) {
                globals.wl_subcompositor = registry.bind(global.name, wl.Subcompositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                globals.wl_shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wp.Viewporter.interface.name) == .eq) {
                globals.wp_viewporter = registry.bind(global.name, wp.Viewporter, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wp.FractionalScaleManagerV1.interface.name) == .eq) {
                globals.wp_fractional_scale_manager = registry.bind(global.name, wp.FractionalScaleManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wp.SinglePixelBufferManagerV1.interface.name) == .eq) {
                globals.wp_single_pixel_buffer_manager = registry.bind(global.name, wp.SinglePixelBufferManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.WindowManagerV1.interface.name) == .eq) {
                globals.rwm = registry.bind(global.name, river.WindowManagerV1, 2) catch return;
            } else if (mem.orderZ(u8, global.interface, river.XkbBindingsV1.interface.name) == .eq) {
                globals.rwm_xkb_bindings = registry.bind(global.name, river.XkbBindingsV1, 2) catch return;
            } else if (mem.orderZ(u8, global.interface, river.LayerShellV1.interface.name) == .eq) {
                globals.rwm_layer_shell = registry.bind(global.name, river.LayerShellV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.InputManagerV1.interface.name) == .eq) {
                globals.rwm_input_manager = registry.bind(global.name, river.InputManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.LibinputConfigV1.interface.name) == .eq) {
                globals.rwm_libinput_config = registry.bind(global.name, river.LibinputConfigV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.XkbConfigV1.interface.name) == .eq) {
                globals.rwm_xkb_config = registry.bind(global.name, river.XkbConfigV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}
