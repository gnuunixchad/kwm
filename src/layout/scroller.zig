const Self = @This();

const std = @import("std");
const log = std.log.scoped(.scroller);

const Context = @import("../context.zig");
const Output = @import("../output.zig");
const Window = @import("../window.zig");


outer_gap: i32,
inner_gap: i32,
mfact: f32,
snap_to_left: bool,


pub fn arrange(self: *const Self, output: *Output) void {
    log.debug("<{*}> arrange windows in output {*}", .{ self, output });

    const context = Context.get();

    const focus_top = context.focus_top_in(output, true) orelse return;

    const master_width: i32 = @intFromFloat(
        @as(f32, @floatFromInt(output.width)) * (focus_top.scroller_mfact orelse self.mfact)
    );
    const height = output.height - 2*self.outer_gap;
    const master_x = if (self.snap_to_left) self.outer_gap else @divFloor(output.width-master_width, 2);
    const y = self.outer_gap;

    focus_top.move(master_x, y);
    focus_top.resize(master_width, height);

    {
        var link = &focus_top.link;
        var x = master_x;
        while (link.prev.? != &context.windows.link) {
            defer link = link.prev.?;
            const window: *Window = @fieldParentPtr("link", link.prev.?);
            if (!window.is_visible_in(output) or window.floating) continue;

            x -= self.inner_gap;
            if (x <= 0) {
                window.hide();
            } else {
                const width: i32 = @intFromFloat(
                    @as(f32, @floatFromInt(output.width)) * (window.scroller_mfact orelse self.mfact)
                );

                x -= width;
                window.unbound_move(x, y);
                window.unbound_resize(width, height);
            }
        }
    }

    {
        var link = &focus_top.link;
        var x = master_x + master_width;
        while (link.next.? != &context.windows.link) {
            defer link = link.next.?;
            const window: *Window = @fieldParentPtr("link", link.next.?);
            if (!window.is_visible_in(output) or window.floating) continue;

            x += self.inner_gap;
            if (x >= output.width) {
                window.hide();
            } else {
                const width: i32 = @intFromFloat(
                    @as(f32, @floatFromInt(output.width)) * (window.scroller_mfact orelse self.mfact)
                );

                window.unbound_move(x, y);
                window.unbound_resize(width, height);
                x += width;
            }
        }
    }
}
