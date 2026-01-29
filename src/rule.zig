const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.rule);

const mvzr = @import("mvzr");

const kwm = @import("kwm");

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


pub const Dimension = struct {
    width: i32,
    height: i32,
};


title: ?Pattern = null,
app_id: ?Pattern = null,
alter_match_fn: ?*const fn(*const Self, ?[]const u8, ?[]const u8) bool = null,

tag: ?u32 = null,
floating: ?bool = null,
dimension: ?Dimension = null,
decoration: ?kwm.WindowDecoration = null,
is_terminal: ?bool = null,
disable_swallow: ?bool = null,
scroller_mfact: ?f32 = null,


pub fn match(self: *const Self, app_id: ?[]const u8, title: ?[]const u8) bool {
    if (self.alter_match_fn) |match_fn| return match_fn(self, app_id, title);

    if (self.app_id) |pattern| {
        if (app_id) |appid| {
            log.debug("try match app_id: `{s}` with {*}({*}: `{s}`)", .{ appid, self, &pattern, pattern.str });

            if (!pattern.is_match(appid)) return false;
        } else return false;
    }

    if (self.title) |pattern| {
        if (title) |title_| {
            log.debug("try match title: `{s}` with {*}({*}: `{s}`)", .{ title_, self, &pattern, pattern.str });

            if (!pattern.is_match(title_)) return false;
        } else return false;
    }

    return true;
}
