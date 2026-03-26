### Description
This mimics the default dwm's monocle layout indicator, user can see how many
windows are stacked in the monocle layout without having to cycle through all
of them.

- Behaviors
    + When there's no non-floating visible windows on the output, display the
      indicator defined in `config.zig`(`[=]` by default).
    + Else replace the indicator with `[n]`, where `n` is the non-floating
      visible windows count.

(Sticky windows are counted if they are non-floating.)

### Download
- [bar-monocle-window-count.patch](./bar-monocle-window-count.patch)

### Authors
- [unixchad](https://codeberg.org/unixchad)
