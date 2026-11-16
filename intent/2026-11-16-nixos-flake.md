---
status: draft
issue: none (issues are disabled on olafkfreund/nixarchy-omapod; see open question 1)
author: olafkfreund
---

# Intent: Install omaPOD on NixOS with a flake

## Problem

omaPOD installs only the Arch/Omarchy way: `omarchy plugin add`, or `install.sh`, which
checks for packages with `pacman` names, copies the code into `~/.local/share/omapod-app`,
writes a launcher script, a desktop entry, an icon, `x-scheme-handler` defaults in
`mimeapps.list`, an optional `omapod-refresh` systemd user timer, and an optional copy of
the bar widget in `~/.config/omarchy/plugins/io.github.arikisonfire.pod`.

On NixOS (and nixarchy, Omarchy on NixOS) none of that is declarative:

- There is no package. The app needs Python with PyGObject and the GTK 4, libadwaita,
  GdkPixbuf, Pango and Graphene typelibs, plus `mpv` on `PATH`; on NixOS that has to be
  wrapped, or it fails at `gi.require_version`.
- The installer writes into `$HOME` imperatively, so a rebuild does not reproduce it and a
  rollback does not undo it.
- Nothing binds global keys to the existing `omapod ctl …` commands (toggle, rewind,
  forward, skip, speed, sleep, show), so playback control from Hyprland is manual.
- The bar widget's settings (`showTitle`, `maxTitleWidth`, `hideWhenStopped`,
  `launchCommand`, `socketPath`) and the app's ~90 settings in `settings.json` cannot be
  set from Nix.
- There is no CI at all: the unit tests (`python3 -B -m unittest discover -s tests -t .`)
  run only when someone remembers to.
- The README documents only the Arch path.

## Proposed outcome

- `nix run github:olafkfreund/nixarchy-omapod` starts omaPOD on any NixOS machine with no
  other setup.
- A NixOS user adds the flake as an input, imports a module, sets one `enable = true`, and
  after `nixos-rebuild switch` has: the `omapod` command, a launcher entry with the icon,
  `podcast://`, `itpc://`, `pcast://` and `antennapod-subscribe://` links opening omaPOD,
  and optionally the hourly refresh timer and the bar widget.
- Every user-facing knob is an option: the refresh timer, the bar widget and its five
  settings, the URL handlers, Hyprland keybindings for each `omapod ctl` action (with
  sensible defaults that can be changed or turned off), and the app settings.
- A GitHub Actions workflow proves on every push and pull request that the package
  builds, the unit tests pass inside the Nix build, and a NixOS VM with the module enabled
  can run `omapod --version`, `omapod ctl state` against a running instance, and has the
  timer and desktop entry in place.
- The README has a NixOS section: flake input, module import, an example with every
  option, and how to update and remove.

## Affected users and systems

- NixOS and nixarchy users of omaPOD (new path); Arch/Omarchy users are unaffected.
- New files: `flake.nix`, `flake.lock`, a Nix package expression, NixOS and/or
  Home Manager module(s), a VM test, `.github/workflows/*.yml`.
- Changed: `README.md`. Possibly `omapod` itself only if packaging exposes a real bug.
- Upstream is `arikisonfire/omapod`; this repo is a fork. The flake should not make
  upstream merges painful.
- No host deploys: nothing here is built on p510 or switched on any machine.

## Constraints

- Must not change app behaviour or the Arch install path (`install.sh`, `manifest.json`,
  marketplace layout).
- Must not make `~/.config/omapod/settings.json` read-only: the app writes it at runtime
  (window size, last page, sync state). Nix-managed settings must be merged in, not
  symlinked over.
- Must not write `credentials.json` or any secret into the Nix store; secrets stay in the
  app (or a file path option pointing outside the store).
- Must not overwrite a user's own choice of app for the podcast URL schemes, matching
  `install.sh`.
- Writing into `~/.config/omarchy/plugins/` makes the Omarchy shell reload every plugin;
  the widget must be installed only when asked for.
- Keybindings must not silently clash with Omarchy/nixarchy defaults; they must be
  overridable and disable-able.
- The tiling test needs `xvfb-run` and `dbus-run-session`; CI either provides them or the
  test stays skipped, said so plainly.
- License stays GPL-3.0-or-later; package meta says so.

## Open questions

1. **Issue number.** Issues are disabled on `olafkfreund/nixarchy-omapod`, so this slug
   has no issue. Enable issues and open one, or proceed without?
2. **Module shape.** Per-user things (keybindings, widget, settings, user timer, MIME
   defaults) fit Home Manager best; a NixOS module can add the package, desktop entry,
   icon and a `systemd.user` timer system-wide. Ship both (NixOS module for install,
   Home Manager module for per-user config), or NixOS only?
3. **Keybindings target.** Bind through Home Manager's
   `wayland.windowManager.hyprland.settings.bind`, or write a nixarchy/Omarchy
   `bindings.lua` snippet (nixarchy shares `~/.config/hypr/bindings.lua` between
   sessions)? And which default keys — e.g. Super+Alt+P toggle, Super+Alt+[ / ] rewind and
   forward, Super+Alt+N skip, Super+Alt+O show — or no defaults, off until set?
4. **App settings scope.** Expose a free-form `settings` attrset merged into
   `settings.json` at activation (covers all ~90 keys, stays in sync with upstream), or
   typed options for a chosen subset (better docs, drifts from upstream)?
5. **CI runner.** NixOS VM tests need KVM; GitHub-hosted `ubuntu-latest` has it. Use
   `nix flake check` there with a Cachix/magic-nix-cache, or only build and unit-test in
   CI and keep the VM test local?
