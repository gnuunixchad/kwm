const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const posix = std.posix;
const log = std.log.scoped(.preprocess);

const mvzr = @import("mvzr");

const State = union(enum) {
    normal,
    @"if",
    @"else",
    elif,
};
const Target = struct {
    hostname: []const u8,
};


pub fn preprocess(allocator: mem.Allocator, file: fs.File) !std.ArrayList(u8) {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var reader_buffer: [1024]u8 = undefined;
    var reader = file.reader(&reader_buffer);
    const f = &reader.interface;

    var hostname_buffer: [posix.HOST_NAME_MAX]u8 = undefined;
    const target: Target = .{
        .hostname = try posix.gethostname(&hostname_buffer),
    };

    const if_pattern = mvzr.compile(
        \\//\s*@if\s*\(.*\)
        \\
    ).?;
    const elif_pattern = mvzr.compile(
        \\//\s*@elif\s*\(.*\)
        \\
    ).?;
    const else_pattern = mvzr.compile(
        \\//\s*@else
        \\
    ).?;
    const end_pattern = mvzr.compile(
        \\//\s*@endif
        \\
    ).?;
    var save = true;
    var matched = false;
    var state: State = .normal;
    while (f.takeDelimiterInclusive('\n')) |line| {
        switch (state) {
            .normal => {
                if (if_pattern.isMatch(line)) {
                    matched = (try match(line, &target)) orelse continue;
                    save = matched;
                    state = .@"if";
                    continue;
                }
            },
            .@"if", .elif => {
                if (end_pattern.isMatch(line)) {
                    save = true;
                    matched = false;
                    state = .normal;
                    continue;
                } else if (else_pattern.isMatch(line)) {
                    save = !matched;
                    state = .@"else";
                    continue;
                } else if (elif_pattern.isMatch(line)) {
                    if (matched) {
                        save = false;
                    } else {
                        matched = (try match(line, &target)) orelse continue;
                        save = matched;
                    }
                    state = .elif;
                    continue;
                }
            },
            .@"else" => {
                if (end_pattern.isMatch(line)) {
                    save = true;
                    matched = false;
                    state = .normal;
                    continue;
                }
            },
        }

        if (save) {
            try result.appendSlice(allocator, line);
        }
    } else |err| if (err != error.EndOfStream) return err;

    try result.append(allocator, 0);
    return result;
}


fn match(line: []const u8, target: *const Target) !?bool {
    inline for (@typeInfo(Target).@"struct".fields) |field_info| {
        const str = parse(line, field_info.name) orelse return null;
        const pattern = mvzr.compile(str) orelse return error.CompileFailed;

        log.debug(field_info.name ++ ": try match {s} with {s}", .{ @field(target, field_info.name), str });

        if (!pattern.isMatch(@field(target, field_info.name))) return false;
    }
    return true;
}


fn parse(line: []const u8, name: []const u8) ?[]const u8 {
    var i = mem.indexOf(u8, line, name) orelse return null;
    i += name.len;
    const end = line.len - 2;

    while (i < end and line[i] == ' ') : (i += 1) {}
    if (line[i] != '=') return null;
    i += 1;

    while (i < end and line[i] == ' ') : (i += 1) {}
    const start = i;

    while (i < end and line[i] != ',') : (i += 1) {}
    return line[start..i];
}
