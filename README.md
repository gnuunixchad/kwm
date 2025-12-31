# kwm - kewuaa's Window Manager

A window manager based on River Wayland Compositor, written in Zig

![tile](./images/tile.png)

![monocle](./images/monocle.png)

![scroller](./images/scroller.png)

## Requirements

- Zig 0.15
- River Wayland compositor 0.4.x (with river-window-management-v1 protocol)

## Features

**Multiple layout:** tile, monocle, scroller, floating

**Tag:** base tags not workspaces (supports separate window layouts for each tag)

**Rule support:** regex rule match

**Bindings:** bindings in different mode such as default, passthrough orelse your custom mode

**Rich window state:** swallow, maximize, fullscreen, fakefullscreen

you could see all config in [config](./src/config.zig)

## Thanks to these reference project

- https://github.com/riverwm/river - River Wayland compositor
- https://github.com/pinpox/river-pwm - River based window manager
- https://codeberg.org/machi/machi - River based window manager
- https://codeberg.org/dwl/dwl - dwm for wayland
- https://codeberg.org/dwl/dwl-patches/src/branch/main/patches/swallow/swallow.patch - swallow window patch for dwl
