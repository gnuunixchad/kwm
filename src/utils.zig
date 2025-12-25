const std = @import("std");
const process = std.process;

const wayland = @import("wayland");
const wl = wayland.client.wl;

pub var allocator: std.mem.Allocator = undefined;


pub fn cycle_list(
    comptime T: type,
    head: *wl.list.Link,
    node: *wl.list.Link,
    tag: @Type(.enum_literal),
) *T {
    var next_node: ?*wl.list.Link = @field(node, @tagName(tag));
    if (next_node) |link| {
        if (link == head) {
            next_node = @field(head, @tagName(tag));
        }
    }

    return @fieldParentPtr("link", next_node.?);
}


pub fn rgba(color: u32) struct { r: u32, g: u32, b: u32, a: u32 } {
    return .{
        .r = @as(u32, (color >> 16) & 0xFF) * (0xFFFF_FFFF / 0xFF),
        .g = @as(u32, (color >> 8) & 0xFF) * (0xFFFF_FFFF / 0xFF),
        .b = @as(u32, (color >> 0) & 0xFF) * (0xFFFF_FFFF / 0xFF),
        .a = 0xFFFF_FFFF,
    };
}
