const std = @import("std");
const posix = std.posix;
const log = std.log.scoped(.kwm);

const wayland = @import("wayland");
const wl = wayland.client.wl;

const utils = @import("kwm/utils.zig");
const types = @import("kwm/types.zig");
const binding = @import("kwm/binding.zig");
const Window = @import("kwm/window.zig");
const Context = @import("kwm/context.zig");

const FDType = enum {
    wayland,
    signal,
    bar_status,
    key_repeat,
};

pub const layout = @import("kwm/layout.zig");
pub const BindingAction = binding.Action;
pub const BindingArg = binding.Arg;
pub const XkbBindingEvent = binding.XkbBinding.Event;
pub const PointerBindingEvent = binding.PointerBinding.Event;
pub const WindowDecoration = Window.Decoration;
pub const State = types.State;
pub const Button = types.Button;
pub const KeyboardRepeatInfo = types.KeyboardRepeatInfo;
pub const KeyboardNumlockState = types.KeyboardNumlockState;
pub const KeyboardCapslockState = types.KeyboardCapslockState;
pub const KeyboardLayout = types.KeyboardLayout;
pub const Keymap = types.Keymap;


pub const init = Context.init;
pub const deinit = Context.deinit;
pub const init_allocator = utils.init_allocator;


pub fn run(wl_display: *wl.Display) !void {
    const context = Context.get();

    const wayland_fd = wl_display.getFd();

    var mask = posix.sigemptyset();
    posix.sigaddset(&mask, posix.SIG.INT);
    posix.sigaddset(&mask, posix.SIG.TERM);
    posix.sigaddset(&mask, posix.SIG.QUIT);
    posix.sigaddset(&mask, posix.SIG.CHLD);
    posix.sigprocmask(posix.SIG.BLOCK, &mask, null);
    const signal_fd = try posix.signalfd(-1, &mask, 1 << @bitOffsetOf(posix.O, "NONBLOCK"));
    defer posix.close(signal_fd);

    const fd_type_num = @typeInfo(FDType).@"enum".fields.len;
    var fd_buffer: [fd_type_num]posix.pollfd = undefined;
    var fd_type_buffer: [fd_type_num]FDType = undefined;
    var poll_fds: std.ArrayList(posix.pollfd) = .initBuffer(&fd_buffer);
    var fd_types: std.ArrayList(FDType) = .initBuffer(&fd_type_buffer);

    log.info("start running", .{});
    defer log.info("stop running", .{});

    while (context.running) {
        defer poll_fds.clearRetainingCapacity();
        defer fd_types.clearRetainingCapacity();

        try poll_fds.appendBounded(.{ .fd = wayland_fd, .events = posix.POLL.IN, .revents = 0 });
        try fd_types.appendBounded(.wayland);

        try poll_fds.appendBounded(.{ .fd = signal_fd, .events = posix.POLL.IN, .revents = 0 });
        try fd_types.appendBounded(.signal);

        if (context.bar_status_fd) |fd| {
            try poll_fds.appendBounded(.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 });
            try fd_types.appendBounded(.bar_status);
        }

        if (context.key_repeat) |key_repeat| {
            if (key_repeat.is_repeating()) {
                try poll_fds.appendBounded(.{ .fd = key_repeat.timer_fd, .events = posix.POLL.IN, .revents = 0 });
                try fd_types.appendBounded(.key_repeat);
            }
        }

        _ = wl_display.flush();
        _ = try posix.poll(poll_fds.items, -1);

        for (fd_types.items, poll_fds.items) |fd_type, poll_fd| {
            if (poll_fd.revents & posix.POLL.IN != 0) {
                switch (fd_type) {
                    .wayland => if (wl_display.dispatch() != .SUCCESS) return error.DispatchFailed,
                    .signal => {
                        const signal_info = try read(posix.siginfo_t, poll_fd.fd) orelse continue;
                        context.handle_signal(signal_info.signo);
                    },
                    .bar_status => context.update_bar_status(),
                    .key_repeat => {
                        const count = try read(u64, poll_fd.fd) orelse continue;
                        context.key_repeat.?.repeat(count);
                    },
                }
            }
        }

    }
}


fn read(comptime T: type, fd: posix.fd_t) !?T {
    var data: T = undefined;
    const buffer: *[@sizeOf(T)]u8 = @ptrCast(&data);
    const nbytes = posix.read(fd, buffer) catch |err| {
        switch (err) {
            error.WouldBlock => return null,
            else => return err,
        }
    };
    if (nbytes != @sizeOf(T)) return null;
    return data;
}
