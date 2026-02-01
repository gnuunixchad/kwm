const Self = @This();

const std = @import("std");
const log = std.log.scoped(.component);

const wayland = @import("wayland");
const wl = wayland.client.wl;

const Context = @import("../context.zig");
const Buffer = @import("buffer.zig");


wl_surface: *wl.Surface,
wl_subsurface: *wl.Subsurface,
buffers: [2]Buffer = undefined,

damaged: bool = true,


pub fn init(self: *Self, parent: *wl.Surface) !void {
    log.debug("<{*}> init", .{ self });

    const context = Context.get();

    const wl_surface = try context.wl_compositor.createSurface();
    errdefer wl_surface.destroy();

    const wl_subsurface = try context.wl_subcompositor.getSubsurface(wl_surface, parent);
    errdefer wl_subsurface.destroy();

    self.* = .{
        .wl_surface = wl_surface,
        .wl_subsurface = wl_subsurface,
        .buffers = .{ .{}, .{} },
    };

    wl_subsurface.setDesync();
}


pub fn deinit(self: *Self) void {
    log.debug("<{*}> deinit", .{ self });

    self.wl_subsurface.destroy();
    self.wl_surface.destroy();
    self.buffers[0].deinit();
    self.buffers[1].deinit();
}


pub fn manage(self: *Self, x: i32, y: i32) void {
    log.debug("<{*}> manage (x: {}, y: {})", .{ self, x, y });

    self.wl_subsurface.setPosition(x, y);
}


pub fn render(self: *Self, buffer: *Buffer) void {
    log.debug("<{*}> rendering", .{ self });

    self.wl_surface.attach(buffer.wl_buffer, 0, 0);
    self.wl_surface.damageBuffer(0, 0, buffer.width, buffer.height);
    self.wl_surface.commit();
}


pub fn next_buffer(self: *Self) ?*Buffer {
    for (0..2) |i| {
        if (!self.buffers[i].busy) {
            self.buffers[i].occupy();
            return &self.buffers[i];
        }
    }
    return null;
}
