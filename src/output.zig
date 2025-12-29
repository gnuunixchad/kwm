const Self = @This();

const std = @import("std");
const math = std.math;
const log = std.log.scoped(.output);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils.zig");
const config = @import("config.zig");
const Context = @import("context.zig");
const Window = @import("window.zig");
const layout = @import("layout.zig");


link: wl.list.Link = undefined,

rwm_output: *river.OutputV1,
rwm_layer_shell_output: ?*river.LayerShellOutputV1,

tag: u32 = 1,
main_tag: u32 = 1,
layout_tag: [32]layout.Type = .{ @as(layout.Type, @enumFromInt(0)) } ** 32,
fullscreen_window: ?*Window = null,

name: u32 = undefined,
x: i32 = undefined,
y: i32 = undefined,
width: i32 = undefined,
height: i32 = undefined,


pub fn create(
    rwm_output: *river.OutputV1,
    rwm_layer_shell_output: ?*river.LayerShellOutputV1,
) !*Self {
    const output = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(output);

    defer log.debug("<{*}> created", .{ output });

    output.* = .{
        .rwm_output = rwm_output,
        .rwm_layer_shell_output = rwm_layer_shell_output,
    };
    output.link.init();

    rwm_output.setListener(*Self, rwm_output_listener, output);

    if (rwm_layer_shell_output) |layer_shell_output| {
        layer_shell_output.setListener(*Self, rwm_layer_shell_output_listener, output);
    }

    return output;
}


pub fn destroy(self: *Self) void {
    defer log.debug("<{*}> destroied", .{ self });

    self.link.remove();
    self.rwm_output.destroy();

    if (self.rwm_layer_shell_output) |rwm_layer_shell_output| {
        rwm_layer_shell_output.destroy();
    }

    utils.allocator.destroy(self);
}


pub fn set_tag(self: *Self, tag: u32) void {
    if (tag == 0) return;

    log.debug("<{*}> set tag: {b}", .{ self, tag });

    self.tag = tag;
    if (self.main_tag & tag == 0) {
        // use the lowest bit 1 as new main tag
        self.main_tag = tag ^ (tag & (tag-1));

        log.debug("<{*}> update main tag to {b}", .{ self, self.main_tag });
    }
}


pub fn toggle_tag(self: *Self, mask: u32) void {
    if (self.tag ^ mask == 0) return;

    log.debug("<{*}> toggle tag: (tag: {b}, mask: {b})", .{ self, self.tag, mask });

    self.tag ^= mask;
    // if there is only one bit 1, set it as new main tag
    if (self.tag & (self.tag-1) == 0) {
        log.debug("<{*}> update main tag to {b}", .{ self, self.tag });

        self.main_tag = self.tag;
    }
}


pub fn current_layout(self: *Self) layout.Type {
    std.debug.assert(self.main_tag != 0 and self.main_tag & (self.main_tag-1) == 0);

    return self.layout_tag[@ctz(self.main_tag)];
}


pub fn set_current_layout(self: *Self, layout_t: layout.Type) void {
    std.debug.assert(self.main_tag != 0 and self.main_tag & (self.main_tag-1) == 0);

    log.debug("<{*}>(tag: {b}) set layout to {s}", .{ self, self.main_tag, @tagName(layout_t) });

    self.layout_tag[@ctz(self.main_tag)] = layout_t;
}


pub fn manage(self: *Self) void {
    layout.arrange(self.current_layout(), self);

    log.debug("<{*}> managed", .{ self });
}


fn rwm_output_listener(rwm_output: *river.OutputV1, event: river.OutputV1.Event, output: *Self) void {
    std.debug.assert(rwm_output == output.rwm_output);

    switch (event) {
        .dimensions => |data| {
            log.debug("<{*}> new dimensions: (width: {}, height: {})", .{ output, data.width, data.height });

            output.width = data.width;
            output.height = data.height;
        },
        .position => |data| {
            log.debug("<{*}> new position: (x: {}, y: {})", .{ output, data.x, data.y });

            output.x = data.x;
            output.y = data.y;
        },
        .removed => {
            log.debug("<{*}> removed, name: {}", .{ output, output.name });

            const context = Context.get();

            context.prepare_remove_output(output);

            output.destroy();
        },
        .wl_output => |data| {
            log.debug("<{*}> wl_output: {}", .{ output, data.name });

            output.name = data.name;
        },
    }
}


fn rwm_layer_shell_output_listener(
    rwm_layer_shell_output: *river.LayerShellOutputV1,
    event: river.LayerShellOutputV1.Event,
    output: *Self,
) void {
    std.debug.assert(rwm_layer_shell_output == output.rwm_layer_shell_output.?);

    switch (event) {
        .non_exclusive_area => |data| {
            log.debug(
                "<{*}> non exclusive area: (width: {}, height: {}, x: {}, y: {})",
                .{ output, data.width, data.height, data.x, data.y },
            );

            output.width = data.width;
            output.height = data.height;
            output.x = data.x;
            output.y = data.y;
        },
    }
}
