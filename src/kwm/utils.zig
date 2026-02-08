const builtins = @import("builtin");
const std = @import("std");
const fs = std.fs;
const fmt = std.fmt;
const mem = std.mem;
const posix = std.posix;
const process = std.process;

const wayland = @import("wayland");
const wl = wayland.client.wl;

pub var allocator: std.mem.Allocator = undefined;


pub inline fn init_allocator(al: *const std.mem.Allocator) void {
    allocator = al.*;
}


pub fn cycle_list(
    comptime T: type,
    head: *wl.list.Link,
    node: *wl.list.Link,
    tag: @Type(.enum_literal),
) *T {
    var next_node: ?*wl.list.Link = @field(node, @tagName(tag));
    if (next_node) |link| {
        if (link == head) {
            next_node = @field(head, @tagName(tag));
        }
    }

    return @fieldParentPtr("link", next_node.?);
}


pub fn rgba(color: u32) struct { r: u32, g: u32, b: u32, a: u32 } {
    return .{
        .r = @as(u32, (color >> 24) & 0xFF) * (0xFFFF_FFFF / 0xFF),
        .g = @as(u32, (color >> 16) & 0xFF) * (0xFFFF_FFFF / 0xFF),
        .b = @as(u32, (color >> 8) & 0xFF) * (0xFFFF_FFFF / 0xFF),
        .a = @as(u32, (color >> 0) & 0xFF) * (0xFFFF_FFFF / 0xFF),
    };
}


// https://codeberg.org/dwl/dwl-patches/src/branch/main/patches/swallow/swallow.patch
pub fn parent_pid(pid: i32) i32 {
    var path_buf: [32]u8 = undefined;
    const path = fmt.bufPrint(
        &path_buf,
        "/proc/{}/stat",
        .{ @as(u32, @intCast(pid)) },
    ) catch return 0;

    const file = fs.openFileAbsolute(path, .{ .mode = .read_only }) catch return 0;
    defer file.close();

    var buf: [256]u8 = undefined;
    const nbytes = file.readAll(&buf) catch return 0;
    const data = buf[0..nbytes];

    var it = mem.splitAny(u8, data, " ");
    _ = it.next(); // pid
    _ = it.next(); // process name
    _ = it.next(); // process state
    const ppid_str = it.next() orelse return 0;

    return fmt.parseInt(i32, ppid_str, 10) catch return 0;
}


pub fn waitpid(pid: posix.pid_t, flags: u32) !posix.WaitPidResult {
    var status: if (builtins.link_libc) c_int else u32 = undefined;
    while (true) {
        const rc = posix.system.waitpid(pid, &status, @intCast(flags));
        const err = posix.errno(rc);
        switch (err) {
            .SUCCESS => return .{
                .pid = @intCast(rc),
                .status = @bitCast(status),
            },
            .INTR => continue,
            .CHILD => return error.ChildProcessDoesNotExist,
            .INVAL => return error.InvalidWaitpidFlags,
            else => return posix.unexpectedErrno(err),
        }
    }
}


extern fn wl_proxy_set_user_data(proxy: *wl.Proxy, data: ?*anyopaque) void;
pub fn set_user_data(comptime T: type, object: *T, comptime DataT: type, data: DataT) void {
    const proxy: *wl.Proxy = @ptrCast(object);
    wl_proxy_set_user_data(proxy, @ptrFromInt(@intFromPtr(data)));
}
