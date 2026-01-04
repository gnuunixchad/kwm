const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.rule);

const mvzr = @import("mvzr");

const Window = @import("window.zig");

pub const Pattern = struct {
    str: []const u8,
    regex: ?mvzr.Regex = null,

    pub fn compile(str: []const u8) @This() {
        return .{
            .str = str,
            .regex = .compile(str),
        };
    }

    pub fn is_match(self: *const @This(), haystack: []const u8) bool {
        const matched = blk: {
            if (self.regex) |regex| {
                break :blk regex.isMatch(haystack);
            } else {
                break :blk mem.order(u8, self.str, haystack) == .eq;
            }
        };
        if (matched) {
            log.debug("<{*}> matched `{s}`", .{ self, haystack });
        }
        return matched;
    }
};


title: ?Pattern = null,
app_id: ?Pattern = null,
alter_match_fn: ?*const fn(*const Self, *const Window) bool = null,

tag: ?u32 = null,
floating: ?bool = null,
decoration: ?Window.Decoration = null,
is_terminal: ?bool = null,
disable_swallow: ?bool = null,


pub fn match(self: *const Self, window: *Window) bool {
    if (self.alter_match_fn) |match_fn| return match_fn(self, window);

    if (self.title) |pattern| {
        if (window.title) |title| {
            log.debug("try match title: `{s}` with {*}({*}: `{s}`)", .{ title, self, &pattern, pattern.str });

            if (!pattern.is_match(title)) return false;
        } else return false;
    }

    if (self.app_id) |pattern| {
        if (window.app_id) |app_id| {
            log.debug("try match app_id: `{s}` with {*}({*}: `{s}`)", .{ app_id, self, &pattern, pattern.str });

            if (!pattern.is_match(app_id)) return false;
        } else return false;
    }

    log.debug("<{*}> matched rule {*}", .{ window, self });

    return true;
}


pub fn apply(self: *const Self, window: *Window) void {
    if (self.tag) |tag| window.set_tag(tag);
    if (self.floating) |floating| window.floating = floating;
    if (self.decoration) |decoration| window.decoration = decoration;
    if (self.is_terminal) |is_terminal| window.is_terminal = is_terminal;
    if (self.disable_swallow) |disable_swallow| window.disable_swallow = disable_swallow;
}
