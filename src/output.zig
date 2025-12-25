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
const Layout = enum {
    tiled,
    float,
};


link: wl.list.Link = undefined,

rwm_output: *river.OutputV1,
rwm_layer_shell_output: ?*river.LayerShellOutputV1,

tag: u32 = 1,
windows: wl.list.Head(Window, .link) = undefined,
current_window: ?*Window = null,

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
    output.windows.init();

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

    {
        var it = self.windows.safeIterator(.forward);
        while (it.next()) |window| {
            window.destroy();
        }
    }

    if (self.rwm_layer_shell_output) |rwm_layer_shell_output| {
        rwm_layer_shell_output.destroy();
    }

    utils.allocator.destroy(self);
}


pub fn add_window(self: *Self, window: *Window) void {
    log.debug("<{*}> add window: {*}", .{ self, window });

    self.windows.prepend(window);
    self.current_window = window;
}


pub fn inherit_windows(self: *Self, windows: *wl.list.Head(Window, .link)) void {
    if (windows.empty()) {
        return;
    }

    log.debug("<{*}> inherit {} windows", .{ self, windows.length() });

    if (self.windows.empty()) {
        self.current_window = windows.first();
    }

    {
        var it = windows.safeIterator(.forward);
        while (it.next()) |window| {
            window.output = self;
        }
    }

    self.windows.appendList(windows);
}


pub fn promote_new_window(self: *Self) void {
    log.debug("<{*}> promote new window", .{ self });

    const former_window = self.current_window.?;
    const current_window = utils.cycle_list(
        Window,
        &self.windows.link,
        &former_window.link,
        .prev,
    );

    self.set_current(
        if (current_window == former_window) null
        else current_window
    );
}


pub fn set_current(self: *Self, window: ?*Window) void {
    log.debug("<{*}> set current window: {*}", .{ self, window });

    self.current_window = window;
}


pub fn manage(self: *Self) void {
    // TODO
    {
        var it = self.windows.safeIterator(.forward);
        while (it.next()) |window| {
            window.manage();
        }
    }

    log.debug("<{*}> managed", .{ self });
}


pub fn render(self: *Self) void {
    defer log.debug("<{*}> rendered", .{ self });

    // TODO
    const context = Context.get();
    const focused = context.focused();
    {
        var it = self.windows.safeIterator(.forward);
        while (it.next()) |window| {
            if (window.visiable(self)) {
                window.set_border(
                    config.window.border_width,
                    if (!context.focus_exclusive() and window == focused)
                        config.window.border_color.focus
                    else config.window.border_color.unfocus
                );
                window.render();
            } else {
                window.hide();
            }
        }
    }
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

            if (output == context.current_output) {
                context.promote_new_output();
            }

            {
                var it = output.windows.safeIterator(.forward);
                while (it.next()) |window| {
                    window.output = null;
                    window.former_output = output.name;
                }
            }

            if (context.current_output) |current_output| {
                current_output.inherit_windows(&output.windows);
            } else {
                context.unhandled_windows.appendList(&output.windows);
            }

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
