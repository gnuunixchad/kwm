const Config = @import("config");

const Output = @import("output.zig");

pub const Type = enum {
    tile,
    grid,
    monocle,
    deck,
    scroller,
    float,
};

pub const tile = @import("layout/tile.zig");
pub const grid = @import("layout/grid.zig");
pub const monocle = @import("layout/monocle.zig");
pub const deck = @import("layout/deck.zig");
pub const scroller = @import("layout/scroller.zig");


pub fn arrange(layout: Type, output: *Output) void {
    const config = Config.get();

    switch (layout) {
        .float => return,
        .tile => config.layout.tile.arrange(output),
        .grid => config.layout.grid.arrange(output),
        .monocle => config.layout.monocle.arrange(output),
        .deck => config.layout.deck.arrange(output),
        .scroller => config.layout.scroller.arrange(output),
    }
}
