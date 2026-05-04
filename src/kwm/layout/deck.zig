const Self = @This();

const std = @import("std");
const log = std.log.scoped(.deck);

const types = @import("../types.zig");
const utils = @import("../utils.zig");
const Context = @import("../context.zig");
const Output = @import("../output.zig");
const Window = @import("../window.zig");

pub const MasterLocation = types.LayoutMasterLocation;


nmaster: i32,
mfact: f32,
inner_gap: i32,
outer_gap: i32,
master_location: MasterLocation,


pub fn arrange(self: *const Self, output: *Output) void {
    log.debug("<{*}> arrange windows in output {*}", .{ self, output });

    const context = Context.get();

    var windows: std.ArrayList(*Window) = .empty;
    defer windows.deinit(utils.allocator);
    {
        var it = context.windows.safeIterator(.forward);
        while (it.next()) |window| {
            if (
                !window.is_visible_in(output)
                or window.floating
            ) continue;
            windows.append(utils.allocator, window) catch |err| {
                log.debug("<{*}> append window failed: {}", .{ self, err });
                return;
            };
        }
    }

    if (windows.items.len == 0) return;

    const output_width = output.exclusive_width() - 2*self.outer_gap;
    const output_height = output.exclusive_height() - 2*self.outer_gap;

    const window_num: i32 = @intCast(windows.items.len);
    const nmaster = @min(window_num, self.nmaster);
    const nstack = window_num - nmaster;

    var master_width: i32 = output_width;
    var master_height: i32 = output_height;
    var stack_width: i32 = 0;
    var stack_height: i32 = 0;

    if (nstack > 0) {
        switch (self.master_location) {
            .left, .right => {
                master_width = @intFromFloat(self.mfact * @as(f32, @floatFromInt(output_width)));
                stack_width = output_width - master_width - self.inner_gap;
            },
            .top, .bottom => {
                master_height = @intFromFloat(self.mfact * @as(f32, @floatFromInt(output_height)));
                stack_height = output_height - master_height - self.inner_gap;
            },
        }
    }

    var i: i32 = 0;
    var master_pos: i32 = 0;
    var master_remain: i32 = 0;
    if (nmaster > 0) {
        switch (self.master_location) {
            .left, .right => {
                const total_height = output_height - (self.inner_gap * (nmaster - 1));
                master_height = @divFloor(total_height, nmaster);
                master_remain = @mod(total_height, nmaster);
            },
            .top, .bottom => {
                const total_width = output_width - (self.inner_gap * (nmaster - 1));
                master_width = @divFloor(total_width, nmaster);
                master_remain = @mod(total_width, nmaster);
            },
        }
    }

    for (windows.items) |window| {
        if (i < nmaster) {
            var x: i32 = undefined;
            var y: i32 = undefined;
            var w: i32 = undefined;
            var h: i32 = undefined;

            var master_size: i32 = undefined;
            switch (self.master_location) {
                .left, .right => {
                    master_size = master_height;
                    if (i < master_remain) master_size += 1;
                },
                .top, .bottom => {
                    master_size = master_width;
                    if (i < master_remain) master_size += 1;
                },
            }

            switch (self.master_location) {
                .left => {
                    x = self.outer_gap;
                    y = self.outer_gap + master_pos;
                    w = master_width;
                    h = master_size;
                },
                .right => {
                    x = self.outer_gap + stack_width + self.inner_gap;
                    y = self.outer_gap + master_pos;
                    w = master_width;
                    h = master_size;
                },
                .top => {
                    x = self.outer_gap + master_pos;
                    y = self.outer_gap;
                    w = master_size;
                    h = master_height;
                },
                .bottom => {
                    x = self.outer_gap + master_pos;
                    y = self.outer_gap + stack_height + self.inner_gap;
                    w = master_size;
                    h = master_height;
                },
            }
            w = @max(0, w);
            h = @max(0, h);
            window.unbound_move(x, y);
            window.unbound_resize(w, h);
            master_pos += master_size + self.inner_gap;
        } else {
            var x: i32 = undefined;
            var y: i32 = undefined;
            var w: i32 = undefined;
            var h: i32 = undefined;
            switch (self.master_location) {
                .left => {
                    x = self.outer_gap + master_width + self.inner_gap;
                    y = self.outer_gap;
                    w = stack_width;
                    h = output_height;
                },
                .right => {
                    x = self.outer_gap;
                    y = self.outer_gap;
                    w = stack_width;
                    h = output_height;
                },
                .top => {
                    x = self.outer_gap;
                    y = self.outer_gap + master_height + self.inner_gap;
                    w = output_width;
                    h = stack_height;
                },
                .bottom => {
                    x = self.outer_gap;
                    y = self.outer_gap;
                    w = output_width;
                    h = stack_height;
                },
            }
            w = @max(0, w);
            h = @max(0, h);
            window.unbound_move(x, y);
            window.unbound_resize(w, h);
        }
        i += 1;
    }
}
