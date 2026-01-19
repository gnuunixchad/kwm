const config = @import("config");

const Output = @import("output.zig");

pub const Type = enum {
    tile,
    grid,
    monocle,
    scroller,
    float,
};

pub const tile = @import("layout/tile.zig");
pub const grid = @import("layout/grid.zig");
pub const monocle = @import("layout/monocle.zig");
pub const scroller = @import("layout/scroller.zig");


pub fn arrange(layout: Type, output: *Output) void {
    switch (layout) {
        .float => return,
        .tile => config.tile.arrange(output),
        .grid => config.grid.arrange(output),
        .monocle => config.monocle.arrange(output),
        .scroller => config.scroller.arrange(output),
    }
}
