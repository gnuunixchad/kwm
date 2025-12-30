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

**Tag instead of workspace:** 32 tag

**Rule support:** regex rule match

**Bindings:** bindings in different mode such as default, passthrough orelse your custom mode

**Lots of actions:** fullscreen(support fakefullscreen), toggle_floating, switch_mode, switch_layout, custom_fn and so on, custom_fn allow you to define your own function, quite flexable

you could see all config in [config](./src/config.zig)

## Thanks to these reference project

- https://github.com/riverwm/river - River Wayland compositor
- https://github.com/pinpox/river-pwm - River based window manager
- https://codeberg.org/machi/machi - River based window manager
- https://codeberg.org/dwl/dwl - dwm for wayland
