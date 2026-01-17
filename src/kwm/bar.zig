const Self = @This();

const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const unicode = std.unicode;
const log = std.log.scoped(.bar);

const wayland = @import("wayland");
const wp = wayland.client.wp;
const wl = wayland.client.wl;
const river = wayland.client.river;
const pixman = @import("pixman");
const fcft = @import("fcft");

const utils = @import("utils");
const config = @import("config");

const Context = @import("context.zig");
const Seat = @import("seat.zig");
const Output = @import("output.zig");
const Buffer = @import("bar/buffer.zig");
const Component = @import("bar/component.zig");

pub var status_buffer = [1]u8 { 0 } ** 256;


font: *fcft.Font,

wl_surface: *wl.Surface = undefined,
rwm_shell_surface: *river.ShellSurfaceV1 = undefined,
rwm_shell_surface_node: *river.NodeV1 = undefined,
wp_viewport: *wp.Viewport = undefined,
static_component: Component = undefined,
dynamic_component: Component = undefined,

output: *Output,

backgournd_damaged: bool = true,
hided: bool = !config.bar.show_default,


pub fn init(self: *Self, output: *Output) !void {
    log.debug("<{*}> init", .{ self });

    const font = load_font(output.scale) catch unreachable;
    errdefer font.destroy();

    self.* = .{
        .font = font,
        .output = output,
    };

    if (!self.hided) {
        try self.show();
    }
}


pub fn deinit(self: *Self) void {
    log.debug("<{*}> deinit", .{ self });

    if (!self.hided) {
        self.hided = true;
        self.hide();
    }
    self.font.destroy();
}


pub inline fn height(self: *Self) i32 {
    return self.font.height;
}


pub fn reload_font(self: *Self) void {
    log.debug("<{*}> reload font", .{ self });

    const font = load_font(self.output.scale) catch return;
    self.font.destroy();
    self.font = font;
}


pub fn handle_click(self: *Self, seat: *const Seat) void {
    log.debug("<{*}> handle click by {*}", .{ self, seat });

    const pointer_x = seat.pointer_position.x;
    const pointer_y = seat.pointer_position.y;
    switch (config.bar.position) {
        .top => {
            if (pointer_y < self.output.y or pointer_y > self.output.y + self.height()) {
                return;
            }
        },
        .bottom => {
            if (pointer_y < self.output.y + self.output.height - self.height() or pointer_y > self.output.y + self.output.height) {
                return;
            }
        }
    }

    const pad = self.height();
    var x: i32 = 0;
    for (0.., config.tags) |i, tag| {
        if (to_utf8(tag)) |utf8| {
            defer utils.allocator.free(utf8);

            const text = self.font.rasterizeTextRunUtf32(utf8, .default) catch |err| {
                log.err("rasterizeTextRunUtf32 failed: {}", .{ err });
                return;
            };
            defer text.destroy();

            const tw: i32 = @intCast(text_width(text));
            defer x += tw + pad;

            if (pointer_x >= x and pointer_x < x + tw + pad) {
                self.output.set_tag(@as(u32, @intCast(1)) << @as(u5, @intCast(i)));
                break;
            }
        }
    }
}


pub fn toggle(self: *Self) void {
    log.debug("<{*}> toggle: {}", .{ self, !self.hided });

    self.hided = !self.hided;
    if (self.hided) {
        self.hide();
    } else {
        self.show() catch |err| {
            self.hided = true;
            log.err("<{*}> failed to show: {}", .{ self, err });
            return;
        };
    }
}


pub fn damage(self: *Self, @"type": enum { all, tags, layout, mode, title, status }) void {
    log.debug("<{*}> damage {s}", .{ self, @tagName(@"type") });

    switch (@"type") {
        .all => {
            self.backgournd_damaged = true;
            self.static_component.damaged = true;
            self.dynamic_component.damaged = true;
        },
        .tags => {
            self.static_component.damaged = true;
            self.dynamic_component.damaged = true;
        },
        else => self.dynamic_component.damaged = true,
    }
}


pub fn render(self: *Self) void {
    if (self.hided) return;

    log.debug("<{*}> rendering", .{ self });

    if (self.static_component.damaged) {
        defer self.static_component.damaged = false;

        self.render_static_component();
    }

    if (self.dynamic_component.damaged) {
        defer self.dynamic_component.damaged = false;

        self.render_dynamic_component();
    }

    if (self.backgournd_damaged) {
        defer self.backgournd_damaged = false;

        self.render_background();
    }
}


fn render_background(self: *Self) void {
    log.debug("<{*}> rendering background", .{ self });

    const context = Context.get();
    const h = self.height();

    self.rwm_shell_surface.syncNextCommit();
    self.rwm_shell_surface_node.placeBottom();
    self.rwm_shell_surface_node.setPosition(0, switch (config.bar.position) {
        .top => 0,
        .bottom => self.output.height - self.height(),
    });

    const rgba = utils.rgba(config.bar.color.normal.bg);
    const buffer = context.wp_single_pixel_buffer_manager.createU32RgbaBuffer(rgba.r, rgba.g, rgba.b, rgba.a) catch |err| {
        log.err("<{*}> create buffer failed: {}", .{ self, err });
        return;
    };
    defer buffer.destroy();

    self.static_component.manage(0, 0);
    self.dynamic_component.manage(self.static_component.width.?, 0);

    self.wl_surface.attach(buffer, 0, 0);
    self.wl_surface.damageBuffer(0, 0, self.output.width, h);
    self.wp_viewport.setDestination(self.output.width, h);
    self.wl_surface.commit();
}


fn render_text(
    self: *const Self,
    buffer: *Buffer,
    text: *const fcft.TextRun,
    c: *const pixman.Color,
    x: i32,
    y: i32,
) i16 {
    const image = pixman.Image.createSolidFill(c) orelse {
        log.err("createSolidFill failed", .{});
        return 0;
    };
    defer _ = image.unref();

    var offset: i32 = 0;
    for (0..text.count) |i| {
        const glyph = text.glyphs[i];
        offset += @intCast(glyph.x);
        pixman.Image.composite32(
            .over,
            image,
            glyph.pix,
            buffer.image,
            0,
            0,
            0,
            0,
            x + offset,
            y + self.font.ascent - glyph.y,
            glyph.width,
            glyph.height,
        );
        offset += @intCast(glyph.advance.x - glyph.x);
        if (offset >= buffer.width) break;
    }
    return @intCast(offset);
}


fn render_str(
    self: *const Self,
    buffer: *Buffer,
    str: []const u8,
    c: *const pixman.Color,
    x: i32,
    y: i32,
) i16 {
    if (to_utf8(str)) |utf8| {
        defer utils.allocator.free(utf8);

        const text = self.font.rasterizeTextRunUtf32(utf8, .default) catch |err| {
            log.err("createU32RgbaBuffer failed: {}", .{ err });
            return 0;
        };
        defer text.destroy();

        return self.render_text(buffer, text, c, x, y);
    } return 0;
}


fn render_static_component(self: *Self) void {
    log.debug("<{*}> rendering static component", .{ self });

    const context = Context.get();

    var texts: [config.tags.len]*const fcft.TextRun = undefined;
    for (0.., config.tags) |i, label| {
        if (to_utf8(label)) |utf8| {
            texts[i] = self.font.rasterizeTextRunUtf32(utf8, .default) catch |err| {
                log.err("rasterizeTextRunUtf32 failed: {}", .{ err });
                return;
            };
            utils.allocator.free(utf8);
        } else {
            log.warn("to_utf8 failed", .{});
            return;
        }
    }

    const pad: u16 = @intCast(self.height());
    const w: u16 = blk: {
        var width: u16 = 0;
        for (texts) |text| {
            width += @intCast(text_width(text));
        }
        width += @intCast(texts.len * pad);
        break :blk width;
    };
    const h: u16 = @intCast(self.height());

    defer {
        for (texts) |text| {
            text.destroy();
        }
    }

    const buffer = self.next_buffer(.static, w, h) orelse return;

    var windows_tag: u32 = 0;
    {
        var it = context.windows.safeIterator(.forward);
        while (it.next()) |window| {
            windows_tag |= window.tag;
        }
    }

    const select_fg = color(config.bar.color.select.fg);
    const select_bg = color(config.bar.color.select.bg);
    const normal_fg = color(config.bar.color.normal.fg);
    const transparent = mem.zeroes(pixman.Color);

    const bg_rect = [_]pixman.Rectangle16 {
        .{
            .x = 0,
            .y = 0,
            .width = w,
            .height = h,
        },
    };
    _ = pixman.Image.fillRectangles(.src, buffer.image, &transparent, 1, &bg_rect);

    var x: i16 = 0;
    const y: i16 = 0;
    const box_size: u16 = @intCast(@divFloor(h, 6) + 2);
    const box_offset: i16 = @intCast(@divFloor(h, 9));
    for (0.., texts) |i, text| {
        const tag: u32 = @as(u32, @intCast(1)) << @as(u5, @intCast(i));

        const is_focused = self.output.tag & tag != 0;

        const tag_width: u16 = @intCast(text_width(text)+pad); 
        defer x += @intCast(tag_width);

        if (is_focused) {
            const tag_rect = [_]pixman.Rectangle16 {
                .{
                    .x = x,
                    .y = y,
                    .width = tag_width,
                    .height = h,
                }
            };
            _ = pixman.Image.fillRectangles(
                .src,
                buffer.image,
                &select_bg,
                1,
                &tag_rect,
            );
        }

        if (windows_tag & tag != 0) {
            const box = [_]pixman.Rectangle16 {
                .{
                    .x = x + box_offset,
                    .y = y,
                    .width = box_size,
                    .height = box_size,
                }
            };
            _ = pixman.Image.fillRectangles(
                .src,
                buffer.image,
                if (is_focused) &transparent else &select_bg,
                1,
                &box,
            );

            if (!is_focused) {
                const border = 1;
                const inner = [_]pixman.Rectangle16 {
                    .{
                        .x = box[0].x + 1,
                        .y = box[0].y + 1,
                        .width = box[0].width - 2*border,
                        .height = box[0].height - 2*border,
                    }
                };
                _ = pixman.Image.fillRectangles(.src, buffer.image, &transparent, 1, &inner);
            }
        }

        _ = self.render_text(
            buffer,
            text,
            if (is_focused) &select_fg else &normal_fg,
            x+@as(i16, @intCast(@divFloor(pad, 2))),
            y,
        );
    }

    self.static_component.render(buffer);
}


fn render_dynamic_component(self: *Self) void {
    log.debug("<{*}> rendering dynamic component", .{ self });

    const context = Context.get();

    const normal_fg = color(config.bar.color.normal.fg);
    const select_bg = color(config.bar.color.select.bg);
    const select_fg = color(config.bar.color.select.fg);
    const transparent = mem.zeroes(pixman.Color);

    const pad: u16 = @intCast(self.height());
    const w: u16 = @intCast(self.output.width-self.static_component.width.?);
    const h: u16 = @intCast(self.height());

    const buffer = self.next_buffer(.dynamic, w, h) orelse return;

    var bg_rect = [_]pixman.Rectangle16 {
        .{
            .x = 0,
            .y = 0,
            .width = w,
            .height = h,
        },
    };
    _ = pixman.Image.fillRectangles(.src, buffer.image, &transparent, 1, &bg_rect);


    var x: i16 = 0;
    const y: i16 = 0;

    x += self.render_str(
        buffer,
        config.layout_tag.getAssertContains(self.output.current_layout()),
        &normal_fg,
        x+@as(i16, @intCast(@divFloor(pad, 2))),
        y,
    ) + @as(i16, @intCast(pad));

    const mode_tag =
        if (config.mode_tag.contains(context.mode)) config.mode_tag.getAssertContains(context.mode)
        else @tagName(context.mode);
    if (mode_tag.len > 0) {
        x += self.render_str(
            buffer,
            mode_tag,
            &normal_fg,
            x+@as(i16, @intCast(@divFloor(pad, 2))),
            y,
        ) + @as(i16, @intCast(pad));
    }

    if (context.focus_top_in(self.output, false)) |window| {
        if (self.output == context.current_output) {
            bg_rect[0].x = x;
            bg_rect[0].width = w - @as(u16, @intCast(x));
            _ = pixman.Image.fillRectangles(.src, buffer.image, &select_bg, 1, &bg_rect);
        }

        if (window.title) |title| {
            x += self.render_str(
                buffer,
                title,
                &select_fg,
                x+@as(i16, @intCast(@divFloor(pad, 2))),
                y,
            ) + @as(i16, @intCast(pad));
        }
    }

    const status_text: []const u8 = switch (config.bar.status) {
        .text => |text| text,
        else => mem.span(@as([*:0]const u8, @ptrCast(&status_buffer))),
    };
    if (status_text.len > 0) {
        if (to_utf8(mem.trimEnd(u8, status_text, "\n "))) |utf8| {
            defer utils.allocator.free(utf8);

            const text = self.font.rasterizeTextRunUtf32(utf8, .default) catch |err| {
                log.err("createU32RgbaBuffer failed: {}", .{ err });
                return;
            };
            defer text.destroy();

            const width = text_width(text);

            x = @intCast(w -| @as(u16, @intCast(width)) -| pad);
            bg_rect[0].x = x;
            bg_rect[0].width = w - @as(u16, @intCast(x));
            _ = pixman.Image.fillRectangles(.src, buffer.image, &transparent, 1, &bg_rect);

            x += self.render_text(
                buffer,
                text,
                &normal_fg,
                x+@as(i16, @intCast(@divFloor(pad, 2))),
                y,
            ) + @as(i16, @intCast(pad));
        }
    }

    self.dynamic_component.render(buffer);
}


fn show(self: *Self) !void {
    std.debug.assert(!self.hided);

    log.debug("<{*}> show", .{ self });

    const context = Context.get();

    const wl_surface = try context.wl_compositor.createSurface();
    errdefer wl_surface.destroy();

    const rwm_shell_surface = try context.rwm.getShellSurface(wl_surface);
    errdefer rwm_shell_surface.destroy();

    const rwm_shell_surface_node = try rwm_shell_surface.getNode();
    errdefer rwm_shell_surface_node.destroy();

    const wp_viewport = try context.wp_viewporter.getViewport(wl_surface);
    errdefer wp_viewport.destroy();

    try self.static_component.init(wl_surface);
    errdefer self.static_component.deinit();

    try self.dynamic_component.init(wl_surface);
    errdefer self.dynamic_component.deinit();

    self.wl_surface = wl_surface;
    self.rwm_shell_surface = rwm_shell_surface;
    self.rwm_shell_surface_node = rwm_shell_surface_node;
    self.wp_viewport = wp_viewport;
    self.damage(.all);
    utils.set_user_data(river.ShellSurfaceV1, rwm_shell_surface, *Self, self);

    if (config.bar.status != .text and !context.is_listening_status()) {
        context.start_listening_status();
    }
}


fn hide(self: *Self) void {
    std.debug.assert(self.hided);

    log.debug("<{*}> hide", .{ self });

    self.static_component.deinit();
    self.static_component = undefined;

    self.dynamic_component.deinit();
    self.dynamic_component = undefined;

    self.wp_viewport.destroy();
    self.wp_viewport = undefined;

    self.rwm_shell_surface.destroy();
    self.rwm_shell_surface = undefined;

    self.rwm_shell_surface_node.destroy();
    self.rwm_shell_surface_node = undefined;

    self.wl_surface.destroy();
    self.wl_surface = undefined;
}


fn next_buffer(self: *Self, @"type": enum { static, dynamic }, width: i32, height_: i32) ?*Buffer {
    log.debug("<{*}> get buffer for {s}", .{ self, @tagName(@"type") });

    const component =  &switch (@"type") {
        .static => self.static_component,
        .dynamic => self.dynamic_component,
    };
    const buffer = component.next_buffer() orelse {
        log.warn("<{*}> next_buffer return null", .{ self });
        return null;
    };
    buffer.init(width, height_) catch |err| {
        log.err("<{*}> init buffer for {s} rendering failed: {}", .{ self, @tagName(@"type"), err });
        return null;
    };
    return buffer;
}


fn load_font(scale: i32) !*fcft.Font {
    var buffer: [12]u8 = undefined;
    const backup_font = "monospace:size=10";
    var fonts = [_][*:0]const u8 { @ptrCast(config.bar.font.ptr), backup_font };
    const attr = try fmt.bufPrint(&buffer, "dpi={}", .{ scale*96 });
    const font = fcft.Font.fromName(&fonts, @ptrCast(attr)) catch |err| {
        log.err("load font `{s}` and backup font `{s}` with attr: {s} failed: {}", .{ config.bar.font, backup_font, attr, err });
        return err;
    };
    return font;
}


fn color(rgba: u32) pixman.Color {
    const c = utils.rgba(rgba);
    return .{
        .red = @truncate(c.r << 8),
        .green = @truncate(c.g << 8),
        .blue = @truncate(c.b << 8),
        .alpha = @truncate(c.a << 8),
    };
}


fn to_utf8(bytes: []const u8) ?[]u32 {
    const utf8 = unicode.Utf8View.init(bytes) catch return null;
    var iter = utf8.iterator();

    var runes = std.ArrayList(u32).initCapacity(utils.allocator, bytes.len) catch return null;
    var i: usize = 0;
    while (iter.nextCodepoint()) |rune| : (i += 1) {
        runes.appendAssumeCapacity(rune);
    }

    return runes.toOwnedSlice(utils.allocator) catch null;
}


fn text_width(text: *const fcft.TextRun) u32 {
    var width: u32 = 0;
    for (0..text.count) |i| {
        width += @intCast(text.glyphs[i].advance.x);
    }
    return width;
}
