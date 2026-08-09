# KeySwitch brand assets

Concept C — the layered switch — is the selected KeySwitch identity. It pairs
two interlocking keyboard layers with the violet status light used throughout
the app.

## Source files

- `keyswitch-logo.svg` is the detailed master for the app icon, website, and
  large-format use.
- `keyswitch-mark.svg` is an optically simplified mark for navigation,
  favicons, and raster exports up to 64 px.

Both SVG files are deterministic source assets. Do not edit the generated PNG
files directly.

## Regenerating the macOS icon catalog

From the repository root:

```sh
swift Scripts/generate_app_icons.swift
```

The script exports every macOS AppIcon size into
`KeySwitchApp/Assets.xcassets/AppIcon.appiconset`. Sizes from 16–64 px use the
compact master; larger sizes use the detailed master.

## Usage

- Keep clear space around the mark equal to the diameter of its violet light.
- Do not recolor the violet light or remove it from the standalone mark.
- Do not place the dark mark directly on a similarly dark surface without its
  rounded-square shell.
- Use the word **KeySwitch** exactly as capitalized here.
