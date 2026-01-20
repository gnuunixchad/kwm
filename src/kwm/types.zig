const build_options = @import("build_options");

const wayland = @import("wayland");
const river = wayland.client.river;

const layout = @import("layout.zig");
const Context = @import("context.zig");

pub const Direction = enum {
    forward,
    reverse,
};

pub const PlacePosition = union(enum) {
    top,
    bottom,
    above: *river.NodeV1,
    below: *river.NodeV1,
};

pub const State = struct {
    layout: ?layout.Type,

    pub fn refresh_current_bar(_: *const @This()) void {
        if (comptime build_options.bar_enabled) {
            const context = Context.get();
            if (context.current_output) |output| {
                output.bar.damage(.dynamic);
            }
        }
    }


    pub fn refresh_all_bar(_: *const @This()) void {
        if (comptime build_options.bar_enabled) {
            const context = Context.get();
            {
                var it = context.outputs.safeIterator(.forward);
                while (it.next()) |output| {
                    output.bar.damage(.dynamic);
                }
            }
        }
    }
};
