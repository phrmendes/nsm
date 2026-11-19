## v1.3.2 (2026-11-19)

### Refactoring

- **cli**: print only the version from the main command ([4c3db38](https://github.com/phrmendes/nsm/commit/4c3db386273e35a780f7fcae53b16a2ace3a9acd))

## v1.3.1 (2026-11-19)

### Fixes

- **cli**: wake a stopped server before the forced kill ([e6fa6f3](https://github.com/phrmendes/nsm/commit/e6fa6f34d2f4b175183cf8ac15fb12be102bc76b))

## v1.3.0 (2026-11-19)

### Features

- ship one Go launcher for every platform ([1f428f0](https://github.com/phrmendes/nsm/commit/1f428f0f09e9fb0e278e725a214c0616000d3620))
- **cli**: support macOS ([8325f9d](https://github.com/phrmendes/nsm/commit/8325f9d148ed47c9fce4e2db240628aea389dadf))

### Fixes

- **cli**: detect a live server on macOS with a connection ([6b8ba5d](https://github.com/phrmendes/nsm/commit/6b8ba5d04da562e6eba48d0fe16c979b92779689))

### Refactoring

- **launcher**: document the functions and drop the Go tests ([627d846](https://github.com/phrmendes/nsm/commit/627d8469242a4b84cb3f115433616403b5abe3af))
- **cli**: replace fzf with the built-in fuzzy list ([6dc28ad](https://github.com/phrmendes/nsm/commit/6dc28ad9da430f913ce34897b6e4da3b4d59d35f))

## v1.2.1 (2026-11-18)

### Fixes

- **cli**: stop waiting when the environment launcher fails

## v1.2.0 (2026-11-18)

### Features

- **plugin**: show the progress of a slow start
- **cli**: start each server inside the direnv or devenv environment

### Refactoring

- **cli**: remove comments from the aliases and a blank line from the picker

## v1.1.3 (2026-11-18)

### Refactoring

- **cli**: stream the picker sources with each --flatten

## v1.1.2 (2026-11-18)

### Fixes

- **install**: print one note for a missing FUSE tool

### Refactoring

- **plugin**: use only vim.ui.select and move the helpers to utils

### Performance

- **cli**: stream the picker rows and skip the server probe

## v1.1.1 (2026-11-17)

### Fixes

- run nsm in servers that the AppImage starts

## v1.1.0 (2026-11-17)

### Features

- add last, current, list --json, version, and completions

### Refactoring

- remove comments that repeat names

## v1.0.1 (2026-11-17)

### Refactoring

- **cli**: show active and inactive sessions

### Performance

- stop waiting on servers that do not answer

## v1.0.0 (2026-11-17)

### Features

- release the first stable version

## v0.2.0 (2026-11-17)

### Features

- **plugin**: add the commands `:Nsm kill` and `:Nsm new`
- **cli**: show the project path of each session and skip busy servers
- **plugin**: connect to SSH hosts from the picker
- **plugin**: check the runtime and add a picker scope
- **nvim**: switch sessions with `vim.ui.select`
- **cli**: replace the kitty tabs with an fzf picker
- **cli**: print failures and warnings in colour
- **cli**: add `-f` as the short flag of `kill --force`
- **cli**: configure the picker and restore session files
- **cli**: replace `connect` with `attach` and add scoped picking
- add Neovim Server Manager

### Fixes

- **install**: warn when the system blocks user namespaces
- **install**: warn when `fusermount` is missing
- **ci**: allow unprivileged user namespaces
- **cli**: reject an answer that is not a number
- **cli**: tell a busy server from a stopped server
- **cli**: harden the fzf picker
- **cli**: ignore a missing `zoxide`
- **nix**: follow the Commitizen version
- **nix**: name the packaged script `nsm`

### Refactoring

- **cli**: list SSH hosts and split the store module
- **plugin**: start sessions asynchronously

### Performance

- **cli**: start the kill client with `--clean`
