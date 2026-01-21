const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.libinput_device);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils");
const config = @import("config");

const InputDevice = @import("input_device.zig");


link: wl.list.Link = undefined,

rwm_libinput_device: *river.LibinputDeviceV1,

input_device: ?*InputDevice = null,

three_finger_drag_support: i32 = 0,
scroll_method_support: river.LibinputDeviceV1.ScrollMethods = undefined,
click_method_support: river.LibinputDeviceV1.ClickMethods = undefined,
send_events_support: river.LibinputDeviceV1.SendEventsModes = undefined,


pub fn create(rwm_libinput_device: *river.LibinputDeviceV1) !*Self {
    const libinput_device = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(libinput_device);

    log.debug("<{*}> created", .{ libinput_device });

    libinput_device.* = .{
        .rwm_libinput_device = rwm_libinput_device,
    };
    libinput_device.link.init();

    rwm_libinput_device.setListener(*Self, rwm_libinput_device_listener, libinput_device);

    return libinput_device;
}


pub fn destroy(self: *Self) void {
    log.debug("<{*}> destroied", .{ self });

    self.link.remove();
    self.rwm_libinput_device.destroy();

    utils.allocator.destroy(self);
}


fn set_tap(self: *Self, state: river.LibinputDeviceV1.TapState) void {
    log.debug("<{*}> set tap state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setTap(state) catch |err| {
        log.err("{*} set tap state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_drag(self: *Self, state: river.LibinputDeviceV1.DragState) void {
    log.debug("<{*}> set drag state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setDrag(state) catch |err| {
        log.err("{*} set drag state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_drag_lock(self: *Self, state: river.LibinputDeviceV1.DragLockState) void {
    log.debug("<{*}> set drag lock state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setDragLock(state) catch |err| {
        log.err("{*} set drag lock state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_three_finger_drag(self: *Self, state: river.LibinputDeviceV1.ThreeFingerDragState) void {
    log.debug("<{*}> set three finger drag state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setThreeFingerDrag(state) catch |err| {
        log.err("{*} set three finger drag state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_tap_button_map(self: *Self, button_map: river.LibinputDeviceV1.TapButtonMap) void {
    log.debug("<{*}> set tap button map to {s}", .{ self, @tagName(button_map) });

    const result = self.rwm_libinput_device.setTapButtonMap(button_map) catch |err| {
        log.err("{*} set tap button map to {s} failed: {}", .{ self, @tagName(button_map), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_natural_scroll(self: *Self, state: river.LibinputDeviceV1.NaturalScrollState) void {
    log.debug("<{*}> set natural scroll state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setNaturalScroll(state) catch |err| {
        log.err("{*} set natural scroll state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_dwt(self: *Self, state: river.LibinputDeviceV1.DwtState) void {
    log.debug("<{*}> set dwt state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setDwt(state) catch |err| {
        log.err("{*} set dwt state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_dwtp(self: *Self, state: river.LibinputDeviceV1.DwtpState) void {
    log.debug("<{*}> set dwtp state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setDwtp(state) catch |err| {
        log.err("{*} set dwtp state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_left_handed(self: *Self, state: river.LibinputDeviceV1.LeftHandedState) void {
    log.debug("<{*}> set left handed state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setLeftHanded(state) catch |err| {
        log.err("{*} set left handed state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_middle_emulation(self: *Self, state: river.LibinputDeviceV1.MiddleEmulationState) void {
    log.debug("<{*}> set middle emulation state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setMiddleEmulation(state) catch |err| {
        log.err("{*} set middle emulation state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_scroll_method(self: *Self, method: river.LibinputDeviceV1.ScrollMethod) void {
    log.debug("<{*}> set scroll method to {s}", .{ self, @tagName(method) });

    const result = self.rwm_libinput_device.setScrollMethod(method) catch |err| {
        log.err("{*} set scroll method to {s} failed: {}", .{ self, @tagName(method), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_scroll_button(self: *Self, button: u32) void {
    log.debug("<{*}> set scroll button to {}", .{ self, button });

    const result = self.rwm_libinput_device.setScrollButton(button) catch |err| {
        log.err("{*} set scroll button to {} failed: {}", .{ self, button, err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_scroll_button_lock(self: *Self, state: river.LibinputDeviceV1.ScrollButtonLockState) void {
    log.debug("<{*}> set scroll button lock state to {s}", .{ self, @tagName(state) });

    const result = self.rwm_libinput_device.setScrollButtonLock(state) catch |err| {
        log.err("{*} set scroll button lock state to {s} failed: {}", .{ self, @tagName(state), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_click_method(self: *Self, method: river.LibinputDeviceV1.ClickMethod) void {
    log.debug("<{*}> set click method to {s}", .{ self, @tagName(method) });

    const result = self.rwm_libinput_device.setClickMethod(method) catch |err| {
        log.err("{*} set click method to {s} failed: {}", .{ self, @tagName(method), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_clickfinger_button_map(self: *Self, button_map: river.LibinputDeviceV1.ClickfingerButtonMap) void {
    log.debug("<{*}> set clickfinger button map to {s}", .{ self, @tagName(button_map) });

    const result = self.rwm_libinput_device.setClickfingerButtonMap(button_map) catch |err| {
        log.err("{*} set clickfinger button map to {s} failed: {}", .{ self, @tagName(button_map), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_send_events(self: *Self, modes: river.LibinputDeviceV1.SendEventsModes) void {
    log.debug("<{*}> set send events modes to (disabled: {}, disabled_on_external_mouse: {})", .{ self, modes.disabled, modes.disabled_on_external_mouse });

    const result = self.rwm_libinput_device.setSendEvents(modes) catch |err| {
        log.err("{*} set send events to (disabled: {}, disabled_on_external_mouse: {}) failed: {}", .{ self, modes.disabled, modes.disabled_on_external_mouse, err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_accel_profile(self: *Self, profile: river.LibinputDeviceV1.AccelProfile) void {
    log.debug("<{*}> set accel profile to {s}", .{ self, @tagName(profile) });

    const result = self.rwm_libinput_device.setAccelProfile(profile) catch |err| {
        log.err("{*} set accel profile to {s} failed: {}", .{ self, @tagName(profile), err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_accel_speed(self: *Self, speed: f64) void {
    log.debug("<{*}> set accel speed to {}", .{ self, speed });

    var buf = [1]f64 { speed };
    var arr = wl.Array.fromArrayList(f64, .initBuffer(&buf));
    const result = self.rwm_libinput_device.setAccelSpeed(&arr) catch |err| {
        log.err("{*} set accel speed to {} failed: {}", .{ self, speed, err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_calibration_matrix(self: *Self, matrix: *const [6]f32) void {
    log.debug("<{*}> set calibration matrix to {any}", .{ self, matrix.* });

    var buf: [6]f32 = undefined;
    mem.copyForwards(f32, &buf, matrix);
    var arr = wl.Array.fromArrayList(f32, .initBuffer(&buf));
    const result = self.rwm_libinput_device.setCalibrationMatrix(&arr) catch |err| {
        log.err("{*} set calibration matrix to {any} failed: {}", .{ self, matrix.*, err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn set_rotation(self: *Self, angle: u32) void {
    log.debug("<{*}> set rotation angle to {}", .{ self, angle });

    const result = self.rwm_libinput_device.setRotation(angle) catch |err| {
        log.err("{*} set rotation angle to {} failed: {}", .{ self, angle, err });
        return;
    };

    result.setListener(*Self, rwm_libinput_result_listener, self);
}


fn is_match(self: *Self, comptime T: type, cfg: *const T) bool {
    if (cfg.pattern) |pattern| {
        if (self.input_device) |input_device| {
            if (input_device.name) |name| {
                return pattern.is_match(name);
            }
        }
        return false;
    }
    return true;
}


fn rwm_libinput_device_listener(rwm_libinput_device: *river.LibinputDeviceV1, event: river.LibinputDeviceV1.Event, libinput_device: *Self) void {
    std.debug.assert(rwm_libinput_device == libinput_device.rwm_libinput_device);

    switch (event) {
        .input_device => |data| {
            log.debug("<{*}> input_device: {*}", .{ libinput_device, data.device });

            const rwm_input_device = data.device orelse return;
            const input_device: *InputDevice = @ptrCast(@alignCast(rwm_input_device.getUserData()));

            log.debug("<{*}> input_device, name: {s}", .{ libinput_device, input_device.name orelse "" });

            libinput_device.input_device = input_device;
        },

        .tap_support => |data| {
            log.debug("<{*}> tap_support, finger_count: {}", .{ libinput_device, data.finger_count });
        },
        .tap_default => |data| {
            log.debug("<{*}> tap_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .tap_current => |data| {
            log.debug("<{*}> tap_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.tap), &config.tap)) return;

            if (data.state != config.tap.value) {
                libinput_device.set_tap(config.tap.value);
            }
        },
        .drag_default => |data| {
            log.debug("<{*}> drag_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .drag_current => |data| {
            log.debug("<{*}> drag_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.drag), &config.drag)) return;

            if (data.state != config.drag.value) {
                libinput_device.set_drag(config.drag.value);
            }
        },
        .drag_lock_default => |data| {
            log.debug("<{*}> drag_lock_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .drag_lock_current => |data| {
            log.debug("<{*}> drag_lock_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.drag_lock), &config.drag_lock)) return;

            if (data.state != config.drag_lock.value) {
                libinput_device.set_drag_lock(config.drag_lock.value);
            }
        },
        .tap_button_map_default => |data| {
            log.debug("<{*}> tap_button_map_default, button_map: {s}", .{ libinput_device, @tagName(data.button_map) });
        },
        .tap_button_map_current => |data| {
            log.debug("<{*}> tap_button_map_current, button_map: {s}", .{ libinput_device, @tagName(data.button_map) });

            if (!libinput_device.is_match(@TypeOf(config.tap_button_map), &config.tap_button_map)) return;

            if (data.button_map != config.tap_button_map.value) {
                libinput_device.set_tap_button_map(config.tap_button_map.value);
            }
        },


        .three_finger_drag_support => |data| {
            log.debug("<{*}> three_finger_drag_support, finger_count: {}", .{ libinput_device, data.finger_count });

            libinput_device.three_finger_drag_support = data.finger_count;
        },
        .three_finger_drag_default => |data| {
            log.debug("<{*}> three_finger_drag_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .three_finger_drag_current => |data| {
            log.debug("<{*}> three_finger_drag_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.three_finger_drag), &config.three_finger_drag)) return;

            if (data.state != config.three_finger_drag.value) {
                switch (config.three_finger_drag.value) {
                    .enabled_3fg => if (libinput_device.three_finger_drag_support < 3) return,
                    .enabled_4fg => if (libinput_device.three_finger_drag_support < 4) return,
                    else => {}
                }
                libinput_device.set_three_finger_drag(config.three_finger_drag.value);
            }
        },


        .natural_scroll_support => |data| {
            log.debug("<{*}> natural_scroll_support, suppported: {}", .{ libinput_device, data.supported });
        },
        .natural_scroll_default => |data| {
            log.debug("<{*}> natural_scroll_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .natural_scroll_current => |data| {
            log.debug("<{*}> natural_scroll_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.natural_scroll), &config.natural_scroll)) return;

            if (data.state != config.natural_scroll.value) {
                libinput_device.set_natural_scroll(config.natural_scroll.value);
            }
        },


        .dwt_support => |data| {
            log.debug("<{*}> dwt_support, suppported: {}", .{ libinput_device, data.supported });
        },
        .dwt_default => |data| {
            log.debug("<{*}> dwt_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .dwt_current => |data| {
            log.debug("<{*}> dwt_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.disable_while_typing), &config.disable_while_typing)) return;

            if (data.state != config.disable_while_typing.value) {
                libinput_device.set_dwt(config.disable_while_typing.value);
            }
        },


        .dwtp_support => |data| {
            log.debug("<{*}> dwtp_support, suppported: {}", .{ libinput_device, data.supported });
        },
        .dwtp_default => |data| {
            log.debug("<{*}> dwtp_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .dwtp_current => |data| {
            log.debug("<{*}> dwtp_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.disable_while_trackpointing), &config.disable_while_trackpointing)) return;

            if (data.state != config.disable_while_trackpointing.value) {
                libinput_device.set_dwtp(config.disable_while_trackpointing.value);
            }
        },


        .left_handed_support => |data| {
            log.debug("<{*}> left_handed_support, supported: {}", .{ libinput_device, data.supported });
        },
        .left_handed_default => |data| {
            log.debug("<{*}> left_handed_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .left_handed_current => |data| {
            log.debug("<{*}> left_handed_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.left_handed), &config.left_handed)) return;

            if (data.state != config.left_handed.value) {
                libinput_device.set_left_handed(config.left_handed.value);
            }
        },


        .middle_emulation_support => |data| {
            log.debug("<{*}> middle_emulation_support, supported: {}", .{ libinput_device, data.supported });
        },
        .middle_emulation_default => |data| {
            log.debug("<{*}> middle_emulation_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .middle_emulation_current => |data| {
            log.debug("<{*}> middle_emulation_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.middle_button_emulation), &config.middle_button_emulation)) return;

            if (data.state != config.middle_button_emulation.value) {
                libinput_device.set_middle_emulation(config.middle_button_emulation.value);
            }
        },


        .scroll_method_support => |data| {
            log.debug(
                "<{*}> scroll_method_support, methods: (two_finger: {}, edge: {}, on_button_down: {})",
                .{ libinput_device, data.methods.two_finger, data.methods.edge, data.methods.on_button_down },
            );

            libinput_device.scroll_method_support = data.methods;
        },
        .scroll_method_default => |data| {
            log.debug("<{*}> scroll_method_default, method: {s}", .{ libinput_device, @tagName(data.method) });
        },
        .scroll_method_current => |data| {
            log.debug("<{*}> scroll_method_current, method: {s}", .{ libinput_device, @tagName(data.method) });

            if (!libinput_device.is_match(@TypeOf(config.scroll_method), &config.scroll_method)) return;

            if (
                data.method != config.scroll_method.value
                and (
                    config.scroll_method.value == .no_scroll
                    or @as(u32, @bitCast(libinput_device.scroll_method_support)) & @as(u32, @intFromEnum(config.scroll_method.value)) != 0
                )
            ) {
                libinput_device.set_scroll_method(config.scroll_method.value);
            }
        },
        .scroll_button_default => |data| {
            log.debug("<{*}> scroll_button_default, button: {}", .{ libinput_device, data.button });
        },
        .scroll_button_current => |data| {
            log.debug("<{*}> scroll_button_current, button: {}", .{ libinput_device, data.button });

            if (!libinput_device.is_match(@TypeOf(config.scroll_button), &config.scroll_button)) return;

            if (data.button != @intFromEnum(config.scroll_button.value)) {
                libinput_device.set_scroll_button(@intFromEnum(config.scroll_button.value));
            }
        },
        .scroll_button_lock_default => |data| {
            log.debug("<{*}> scroll_button_lock_default, state: {s}", .{ libinput_device, @tagName(data.state) });
        },
        .scroll_button_lock_current => |data| {
            log.debug("<{*}> scroll_button_lock_current, state: {s}", .{ libinput_device, @tagName(data.state) });

            if (!libinput_device.is_match(@TypeOf(config.scroll_button_lock), &config.scroll_button_lock)) return;

            if (data.state != config.scroll_button_lock.value) {
                libinput_device.set_scroll_button_lock(config.scroll_button_lock.value);
            }
        },


        .click_method_support => |data| {
            log.debug("<{*}> click_method_support, methods: (button_areas: {}, clickfinger: {})", .{ libinput_device, data.methods.button_areas, data.methods.clickfinger });

            libinput_device.click_method_support = data.methods;
        },
        .click_method_default => |data| {
            log.debug("<{*}> click_method_default, method: {s}", .{ libinput_device, @tagName(data.method) });
        },
        .click_method_current => |data| {
            log.debug("<{*}> click_method_current, method: {s}", .{ libinput_device, @tagName(data.method) });

            if (!libinput_device.is_match(@TypeOf(config.click_method), &config.click_method)) return;

            if (
                data.method != config.click_method.value
                and (
                        config.click_method.value == .none
                        or @as(u32, @bitCast(libinput_device.click_method_support)) & @as(u32, @intFromEnum(config.click_method.value)) != 0
                    )
            ) {
                libinput_device.set_click_method(config.click_method.value);
            }
        },
        .clickfinger_button_map_default => |data| {
            log.debug("<{*}> clickfinger_button_map_default, button_map: {s}", .{ libinput_device, @tagName(data.button_map) });
        },
        .clickfinger_button_map_current => |data| {
            log.debug("<{*}> clickfinger_button_map_current, button_map: {s}", .{ libinput_device, @tagName(data.button_map) });

            if (!libinput_device.is_match(@TypeOf(config.clickfinger_button_map), &config.clickfinger_button_map)) return;

            if (data.button_map != config.clickfinger_button_map.value) {
                libinput_device.set_clickfinger_button_map(config.clickfinger_button_map.value);
            }
        },


        .send_events_support => |data| {
            log.debug("<{*}> send_events_support, modes: (disabled: {}, disabled_on_external_mouse: {})", .{ libinput_device, data.modes.disabled, data.modes.disabled_on_external_mouse });
        },
        .send_events_default => |data| {
            log.debug("<{*}> send_events_default, mode: (disabled: {}, disabled_on_external_mouse: {})", .{ libinput_device, data.mode.disabled, data.mode.disabled_on_external_mouse });
        },
        .send_events_current => |data| {
            log.debug("<{*}> send_events_current, mode: (disabled: {}, disabled_on_external_mouse: {})", .{ libinput_device, data.mode.disabled, data.mode.disabled_on_external_mouse });

            if (!libinput_device.is_match(@TypeOf(config.send_events_modes), &config.send_events_modes)) return;

            if (
                @as(u32, @bitCast(data.mode)) != @as(u32, @intFromEnum(config.send_events_modes.value))
                and (
                    config.send_events_modes.value == .enabled
                    or @as(u32, @bitCast(libinput_device.send_events_support)) & @as(u32, @intFromEnum(config.send_events_modes.value)) != 0
                )
            ) {
                libinput_device.set_send_events(@bitCast(@as(u32, @intFromEnum(config.send_events_modes.value))));
            }
        },


        .accel_profiles_support => |data| {
            log.debug("<{*}> accel_profiles_support, profiles: (flat: {}, adaptive: {}, custom: {})", .{ libinput_device, data.profiles.flat, data.profiles.adaptive, data.profiles.custom });
        },
        .accel_profile_default => |data| {
            log.debug("<{*}> accel_profile_default, profile: {s}", .{ libinput_device, @tagName(data.profile) });
        },
        .accel_profile_current => |data| {
            log.debug("<{*}> accel_profile_current, profile: {s}", .{ libinput_device, @tagName(data.profile) });

            if (!libinput_device.is_match(@TypeOf(config.accel_profile), &config.accel_profile)) return;

            if (data.profile != config.accel_profile.value) {
                libinput_device.set_accel_profile(config.accel_profile.value);
            }
        },
        .accel_speed_default => |data| {
            log.debug("<{*}> accel_speed_default, speed: {any}", .{ libinput_device, data.speed.slice(f64) });
        },
        .accel_speed_current => |data| {
            log.debug("<{*}> accel_speed_current, speed: {any}", .{ libinput_device, data.speed.slice(f64) });

            if (!libinput_device.is_match(@TypeOf(config.accel_speed), &config.accel_speed)) return;

            if (@abs(data.speed.slice(f64)[0] - config.accel_speed.value) > 1e-6) {
                libinput_device.set_accel_speed(config.accel_speed.value);
            }
        },


        .calibration_matrix_support => |data| {
            log.debug("<{*}> calibration_matrix_support, supported: {}", .{ libinput_device, data.supported });
        },
        .calibration_matrix_default => |data| {
            log.debug("<{*}> calibration_matrix_default, matrix: {any}", .{ libinput_device, data.matrix.slice(f32) });
        },
        .calibration_matrix_current => |data| {
            log.debug("<{*}> calibration_matrix_current, matrix: {any}", .{ libinput_device, data.matrix.slice(f32) });

            if (!libinput_device.is_match(@TypeOf(config.calibration_matrix), &config.calibration_matrix)) return;

            if (config.calibration_matrix.value) |matrix| {
                const current_matrix = data.matrix.slice(f32);
                const eq = for (0..6) |i| {
                    if (@abs(current_matrix[i] - matrix[i]) > 1e-6) {
                        break false;
                    }
                } else true;
                if (!eq) {
                    libinput_device.set_calibration_matrix(&matrix);
                }
            }
        },


        .rotation_support => |data| {
            log.debug("<{*}> rotation_support, supported: {}", .{ libinput_device, data.supported });
        },
        .rotation_default => |data| {
            log.debug("<{*}> rotation_default, angle: {}", .{ libinput_device, data.angle });
        },
        .rotation_current => |data| {
            log.debug("<{*}> rotation_current, angle: {}", .{ libinput_device, data.angle });

            if (!libinput_device.is_match(@TypeOf(config.rotation_angle), &config.rotation_angle)) return;

            if (data.angle != config.rotation_angle.value) {
                libinput_device.set_rotation(config.rotation_angle.value);
            }
        },


        .removed => {
            log.debug("<{*}> removed", .{ libinput_device });

            libinput_device.destroy();
        },
    }
}


fn rwm_libinput_result_listener(rwm_libinput_result: *river.LibinputResultV1, event: river.LibinputResultV1.Event, rwm_libinput_device: *Self) void {
    _ = rwm_libinput_device;

    log.debug("<{*}> configuration result: {s}", .{ rwm_libinput_result, @tagName(event) });

    rwm_libinput_result.destroy();
}
