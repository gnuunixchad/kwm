const config = @import("config");

const Output = @import("output.zig");

pub const Type = enum {
    tile,
    monocle,
    scroller,
    float,
};

pub const tile = @import("layout/tile.zig");
pub const monocle = @import("layout/monocle.zig");
pub const scroller = @import("layout/scroller.zig");


pub fn arrange(layout: Type, output: *Output) void {
    switch (layout) {
        .float => return,
        .tile => config.tile.arrange(output),
        .monocle => config.monocle.arrange(output),
        .scroller => config.scroller.arrange(output),
    }
}
