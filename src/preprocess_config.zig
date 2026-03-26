const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const heap = std.heap;
const process = std.process;

const preprocess = @import("config/preprocess.zig");


pub fn main() !void {
    var input: ?[]const u8 = null;
    var output: ?[]const u8 = null;
    var args = process.args();
    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-i")) {
            input = args.next();
        } else if (mem.eql(u8, arg, "-o")) {
            output = args.next();
        }
    }

    const input_file = try fs.cwd().openFile(
        input orelse return error.MissingInput,
        .{ .mode = .read_only },
    );
    defer input_file.close();

    const output_file = try fs.createFileAbsolute(output orelse return error.MissingOutput, .{});
    defer output_file.close();

    var buffer = try preprocess.preprocess(heap.c_allocator, input_file);
    defer buffer.deinit(heap.c_allocator);

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(&output_buffer);
    const writer = &output_writer.interface;
    try writer.writeAll(buffer.items[0..buffer.items.len-1:0]);
    try writer.flush();
}
