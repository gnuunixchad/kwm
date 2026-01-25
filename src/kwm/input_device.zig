const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.input_device);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils");
const config = @import("config");

const types = @import("types.zig");


link: wl.list.Link = undefined,

rwm_input_device: *river.InputDeviceV1,

new: bool = true,
name: ?[]const u8 = null,
type: union(river.InputDeviceV1.Type) {
    keyboard: ?types.KeyboardRepeatInfo,
    pointer: ?f64,
    touch,
    tablet,
} = undefined,


pub fn create(rwm_input_device: *river.InputDeviceV1) !*Self {
    const input_device = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(input_device);

    log.debug("<{*}> created", .{ input_device });

    input_device.* = .{
        .rwm_input_device = rwm_input_device,
    };
    input_device.link.init();

    rwm_input_device.setListener(*Self, rwm_input_device_listener, input_device);

    return input_device;
}


pub fn destroy(self: *Self) void {
    log.debug("<{*}> destroied", .{ self });

    if (self.name) |name| {
        utils.allocator.free(name);
    }

    self.link.remove();
    self.rwm_input_device.destroy();

    utils.allocator.destroy(self);
}


pub fn manage(self: *Self) void {
    log.debug("<{*}> manage", .{ self });

    if (self.new) {
        self.new = false;
        self.apply_config();
    }
}


fn apply_config(self: *Self) void {
    log.debug("<{*}> apply config", .{ self });

    switch (self.type) {
        .keyboard => |*info| {
            if (self.get_from_config(types.KeyboardRepeatInfo, &config.repeat_info)) |repeat_info| {
                if (info.* == null or info.*.?.rate != repeat_info.rate or info.*.?.delay != repeat_info.delay) {
                    log.debug("<{*}> set repeat info: (rate: {}, delay: {})", .{ self, repeat_info.rate, repeat_info.delay});

                    self.rwm_input_device.setRepeatInfo(repeat_info.rate, repeat_info.delay);
                    info.* = repeat_info;
                }
            }
        },
        .pointer => |*factor| {
            if (self.get_from_config(f64, &config.scroll_factor)) |scroll_factor| {
                if (factor.* == null or @abs(factor.*.?-scroll_factor) > 1e-6) {
                    log.debug("<{*}> set scroll factor: {}", .{ self, scroll_factor });

                    self.rwm_input_device.setScrollFactor(.fromDouble(scroll_factor));
                    factor.* = scroll_factor;
                }
            }
        },
        else => {}
    }
}


fn set_name(self: *Self, name: []const u8) void {
    if (self.name) |name_| {
        utils.allocator.free(name_);
        self.name = null;
    }
    self.name = utils.allocator.dupe(u8, name) catch null;
}


inline fn get_from_config(self: *const Self, comptime T: type, cfg: *const config.InputConfig(T)) ?T {
    return switch (cfg.*) {
        .value => |value| value,
        .func => |func| func(self.name),
    };
}


fn rwm_input_device_listener(rwm_input_device: *river.InputDeviceV1, event: river.InputDeviceV1.Event, input_device: *Self) void {
    std.debug.assert(rwm_input_device == input_device.rwm_input_device);

    switch (event) {
        .type => |data| {
            log.debug("<{*}> type: {s}", .{ input_device, @tagName(data.type) });

            input_device.type = switch (data.type) {
                .keyboard => .{ .keyboard = null },
                .pointer => .{ .pointer = null },
                .touch => .touch,
                .tablet => .tablet,
                else => return,
            };
        },
        .name => |data| {
            log.debug("<{*}> name: {s}", .{ input_device, data.name });

            input_device.set_name(mem.span(data.name));
        },
        .removed => {
            log.debug("<{*}> removed", .{ input_device });

            input_device.destroy();
        }
    }
}
