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
