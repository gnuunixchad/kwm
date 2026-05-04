const Self = @This();

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

pub const Tile = @import("layout/tile.zig");
pub const Grid = @import("layout/grid.zig");
pub const Monocle = @import("layout/monocle.zig");
pub const Deck = @import("layout/deck.zig");
pub const Scroller = @import("layout/scroller.zig");


tile: Tile,
grid: Grid,
monocle: Monocle,
deck: Deck,
scroller: Scroller,
