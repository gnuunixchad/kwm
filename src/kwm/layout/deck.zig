const Self = @This();

const std = @import("std");
const log = std.log.scoped(.deck);

const utils = @import("../utils.zig");
const Context = @import("../context.zig");
const Output = @import("../output.zig");
const Window = @import("../window.zig");

inner_gap: i32,
outer_gap: i32,

pub fn arrange(self: *const Self, output: *Output) void {
    log.debug("<{*}> arrange windows in output {*}", .{ self, output });

    const context = Context.get();

    var windows: std.ArrayList(*Window) = .empty;
    defer windows.deinit(utils.allocator);

    var it = context.windows.safeIterator(.forward);
    while (it.next()) |window| {
        if (window.is_visible_in(output) and !window.floating)
            windows.append(utils.allocator, window) catch |err| {
                log.err("<{*}> append failed: {}", .{ self, err });
                return;
            };
    }

    if (windows.items.len == 0) return;

    const w = output.exclusive_width() - 2 * self.outer_gap;
    const h = output.exclusive_height() - 2 * self.outer_gap;

    if (windows.items.len == 1) {
        windows.items[0].unbound_move(self.outer_gap, self.outer_gap);
        windows.items[0].unbound_resize(w, h);
        return;
    }

    const master_w = @divFloor(w, 2);
    const stack_w = w - master_w - self.inner_gap;

    for (windows.items, 0..) |window, i| {
        if (i == 0) {
            window.unbound_move(self.outer_gap, self.outer_gap);
            window.unbound_resize(master_w, h);
        } else {
            window.unbound_move(
                self.outer_gap + master_w + self.inner_gap,
                self.outer_gap
            );
            window.unbound_resize(stack_w, h);
        }
    }
}
