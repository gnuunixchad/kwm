### Description
>[!note]
> This patch has been merged into upstream.

Change the focusing tag to the next/previous occupied one.
- When the output has no occupied tags, each focused tag shifts to its
  next/previous tag.
- When the focused tags are all occupied tags, each focused tag shifts to its
  next/previous occupied tag.

Default keybindings:
- shift next: `<Super + apostrophe>`(`'`)
- shift prev: `<Super + semicolon>` (`;`)

### Download
- [shifttags.patch](./shifttags.patch)

### Authors
- [unixchad](https://codeberg.org/unixchad)
