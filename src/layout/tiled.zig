const std = @import("std");
const log = std.log.scoped(.tiled);

const Output = @import("../output.zig");


pub fn arrange(output: *Output) void {
    log.debug("arange windows in output: {*}", .{ output });

    // TODO
}
