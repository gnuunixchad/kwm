const Self = @This();

const std = @import("std");
const log = std.log.scoped(.monocle);

const Context = @import("../context.zig");
const Output = @import("../output.zig");


gap: i32,


pub fn arrange(self: *const Self, output: *Output) void {
    log.debug("<{*}> arrange windows in output {*}", .{ self, output });

    const context = Context.get();
    const state = output.get_current_per_tag_state();

    const focus_top = context.focus_top_in(output, true) orelse return;
    const available_width = output.exclusive_width() - 2*state.monocle_gap;
    const available_height = output.exclusive_height() - 2*state.monocle_gap;
    {
        var it = context.windows.safeIterator(.forward);
        while (it.next()) |window| {
            if (!window.is_visible_in(output) or window.floating) continue;
            if (window != focus_top) window.hide();
            window.unbound_move(state.monocle_gap, state.monocle_gap);
            window.unbound_resize(available_width, available_height);
        }
    }
}
