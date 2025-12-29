const Self = @This();

const std = @import("std");
const log = std.log.scoped(.scroller);

const config = @import("../config.zig");
const Context = @import("../context.zig");
const Output = @import("../output.zig");
const Window = @import("../window.zig");


gap: i32,
mfact: f32,


pub fn arrange(self: *const Self, output: *Output) void {
    log.debug("<{*}> arrange windows in output {*}", .{ self, output });

    const context = Context.get();

    const focus_top = context.focus_top_in(output, true) orelse return;

    const master_width: i32 = @intFromFloat(@as(f32, @floatFromInt(output.width)) * self.mfact);
    const height = output.height - 2*self.gap - 2*config.border_width;
    const master_x = @divFloor(output.width-master_width, 2);
    const y = self.gap + config.border_width;

    focus_top.move(master_x, y);
    focus_top.resize(master_width, height);

    {
        var link = &focus_top.link;
        var x = master_x;
        while (link.prev.? != &context.windows.link) {
            defer link = link.prev.?;
            const window: *Window = @fieldParentPtr("link", link.prev.?);
            if (!window.is_visiable_in(output) or window.floating) continue;

            x -= self.gap + 2*config.border_width;
            if (x <= 0) {
                window.hide();
            } else {
                const width = master_width;

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
            if (!window.is_visiable_in(output) or window.floating) continue;

            x += self.gap + 2*config.border_width;
            if (x >= output.width) {
                window.hide();
            } else {
                const width = master_width;

                window.unbound_move(x, y);
                window.unbound_resize(width, height);
                x += width;
            }
        }
    }
}
