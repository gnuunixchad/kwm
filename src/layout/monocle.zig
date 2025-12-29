const Self = @This();

const std = @import("std");
const log = std.log.scoped(.monocle);

const config = @import("../config.zig");
const Context = @import("../context.zig");
const Output = @import("../output.zig");


gap: i32,


pub fn arrange(self: *const Self, output: *Output) void {
    log.debug("<{*}> arrange windows in output {*}", .{ self, output });

    const context = Context.get();

    const focus_top = context.focus_top_in(output, true) orelse return;
    const available_width = output.width - 2*self.gap - 2*config.border_width;
    const available_height = output.height - 2*self.gap - 2*config.border_width;
    {
        var it = context.windows.safeIterator(.forward);
        while (it.next()) |window| {
            if (!window.is_visiable_in(output) or window.floating) continue;
            if (window != focus_top) window.hide();
            window.move(self.gap+config.border_width, self.gap+config.border_width);
            window.resize(available_width, available_height);
        }
    }
}
