# <img src="./misc/kwm-repo.png" width="24"/> My build of [kwm](https://github.com/kewuaa/kwm) - kewuaa's Window Manager

A window manager based on River Wayland Compositor, written in Zig

![tile](./misc/tile.png)

![grid](./misc/grid.png)

![monocle](./misc/monocle.png)

![scroller](./misc/scroller.png)

## Requirements

- Zig 0.15
- River Wayland compositor 0.4.x (with river-window-management-v1 protocol)

## Features

**Multiple layout:** tile, grid, monocle, scroller, floating

**Tag:** base tags not workspaces (supports separate window layouts for each tag)

**Rule support:** regex rule match

**Bindings:** bindings in different mode such as default, passthrough orelse your custom mode

**Rich window state:** swallow, maximize, fullscreen, fakefullscreen

**With simple status bar:** dwm like bar

## build

```zig
zig build -Doptimize=ReleaseSafe
```

It will try to find `config.zig` as config file. If not found, will create it from `config.def.zig` as backup.

You can use `-Dconfig` to specify custom config file path, `-Dbar` to enable/disable status bar, default is true, `-Doptimize` to specify build mode.

## configuration

Make your custom modifications in `config.zig`.

## Thanks to these reference project

- https://github.com/riverwm/river - River Wayland compositor
- https://github.com/pinpox/river-pwm - River based window manager
- https://codeberg.org/machi/machi - River based window manager
- https://codeberg.org/dwl/dwl - dwm for wayland
- https://codeberg.org/dwl/dwl-patches/src/branch/main/patches/swallow/swallow.patch - swallow window patch for dwl
