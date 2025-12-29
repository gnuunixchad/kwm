const config = @import("config.zig");
const Output = @import("output.zig");

pub const Type = enum {
    tile,
    monocle,
    scroller,
    float,
};


pub fn arrange(layout: Type, output: *Output) void {
    switch (layout) {
        .tile => config.layout.tile.arrange(output),
        .monocle => config.layout.monocle.arrange(output),
        .scroller => config.layout.scroller.arrange(output),
        .float => {}
    }
}
