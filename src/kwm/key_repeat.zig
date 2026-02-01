const Self = @This();

const std = @import("std");
const mem = std.mem;
const time = std.time;
const posix = std.posix;
const log = std.log.scoped(.key_repeat);

const config = @import("config");

const binding = @import("binding.zig");
const Context = @import("context.zig");


xkb_binding: ?*binding.XkbBinding = null,

timer_fd: posix.fd_t,


pub fn init(self: *Self) !void {
    log.debug("<{*}> init", .{ self });

    const timer_fd = try posix.timerfd_create(.MONOTONIC, .{ .NONBLOCK = true });
    errdefer posix.close(timer_fd);

    self.* = .{
        .timer_fd = timer_fd,
    };
}


pub fn deinit(self: *Self) void {
    log.debug("<{*}> deinit", .{ self });

    posix.close(self.timer_fd);
}


pub fn prepare_repeat(self: *Self, xkb_binding: *binding.XkbBinding) void {
    if (self.is_repeating()) return;

    log.debug("<{*}> start repeating {*}", .{ self, xkb_binding });

    const itimerspec: posix.system.itimerspec = .{
        .it_value = .{ .sec = 0, .nsec = config.repeat_delay*time.ns_per_ms },
        .it_interval = .{ .sec = 0, .nsec = @divFloor(time.ns_per_s, config.repeat_rate) },
    };
    posix.timerfd_settime(self.timer_fd, .{ .ABSTIME = false }, &itimerspec, null) catch |err| {
        log.err("<{*}> call timerfd_settime of timer_fd failed: {}", .{ self, err });
        return;
    };

    self.xkb_binding = xkb_binding;
}


pub fn repeat(self: *Self, count: u64) void {
    if (!self.is_repeating()) return;

    log.debug("<{*}> repeat, count: {}", .{ self, count });

    const context = Context.get();

    for (0..count) |_| {
        self.xkb_binding.?.seat.append_action(self.xkb_binding.?.action);
    }

    context.rwm.manageDirty();
}


pub fn stop(self: *Self, xkb_binding: *binding.XkbBinding) void {
    if (!self.is_repeating()) return;

    if (xkb_binding != self.xkb_binding.?) return;

    log.debug("<{*}> stop repeating {*}", .{ self, self.xkb_binding.? });

    self.reset_timer() catch |err| {
        log.err("<{*}> reset timer failed: {}", .{ self, err });
    };

    self.xkb_binding = null;
}


pub inline fn is_repeating(self: *const Self) bool {
    return self.xkb_binding != null;
}


fn reset_timer(self: *Self) !void {
    log.debug("<{*}> reset timer", .{ self });

    const itimerspec = mem.zeroes(posix.system.itimerspec);
    try posix.timerfd_settime(self.timer_fd, .{ .ABSTIME = false }, &itimerspec, null);
}
