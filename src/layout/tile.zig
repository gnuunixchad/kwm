const Self = @This();

const std = @import("std");
const log = std.log.scoped(.tiled);

const utils = @import("../utils.zig");
const config = @import("../config.zig");
const Context = @import("../context.zig");
const Output = @import("../output.zig");
const Window = @import("../window.zig");


nmaster: i32,
mfact: f32,
gap: i32,


pub fn arrange(self: *const Self, output: *Output) void {
    log.debug("<{*}> arrange windows in output {*}", .{ self, output });

    const context = Context.get();

    var windows: std.ArrayList(*Window) = .empty;
    defer windows.deinit(utils.allocator);
    {
        var it = context.windows.safeIterator(.forward);
        while (it.next()) |window| {
            if (
                !window.is_visiable_in(output)
                or window.floating
            ) continue;
            windows.append(utils.allocator, window) catch |err| {
                log.debug("<{*}> append window failed: {}", .{ self, err });
                return;
            };
        }
    }

    if (windows.items.len == 0) return;

    var master_width: i32 = undefined;
    var master_height: i32 = undefined;
    var stack_width: i32 = 0;
    var stack_height: i32 = 0;
    const window_num: i32 = @intCast(windows.items.len);
    if (windows.items.len > self.nmaster) {
        {
            const available_width = output.width - 3*self.gap - 4*config.border_width;
            master_width = @intFromFloat(@as(f32, @floatFromInt(available_width)) * self.mfact);
            stack_width = available_width - master_width;
        }
        {
            const available_height = output.height - (self.nmaster+1)*self.gap - 2*self.nmaster*config.border_width;
            master_height = @divFloor(available_height, self.nmaster);
        }
        {
            const available_height = output.height - (window_num-self.nmaster+1)*self.gap - 2*(window_num-self.nmaster)*config.border_width;
            stack_height = @divFloor(available_height, window_num-self.nmaster);
        }
    } else {
        {
            const available_width = output.width - 2*self.gap - 2*config.border_width;
            master_width = available_width;
        }
        {
            const available_height = output.height - (window_num+1)*self.gap - 2*window_num*config.border_width;
            master_height = @divFloor(available_height, window_num);
        }
    }

    const master_x = self.gap + config.border_width;
    const stack_x = master_width + 2*self.gap + 2*config.border_width;
    var master_y = self.gap + config.border_width;
    var stack_y = self.gap + config.border_width;
    for (0.., windows.items) |i, window| {
        if (i < self.nmaster) {
            window.move(master_x, master_y);
            window.resize(master_width, master_height);
            master_y += master_height + self.gap + config.border_width;
        } else {
            window.move(stack_x, stack_y);
            window.resize(stack_width, stack_height);
            stack_y += stack_height + self.gap + config.border_width;
        }
    }
}
