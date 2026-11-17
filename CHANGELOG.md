## v1.0.0 (2026-11-17)

### Feat

- release the first stable version

## v0.2.0 (2026-11-17)

### Feat

- **plugin**: add :Nsm kill and :Nsm new
- **cli**: show project paths and skip busy servers
- **plugin**: connect to SSH hosts from the picker
- **plugin**: validate runtime and add picker scope
- **nvim**: switch sessions with vim.ui.select
- **cli**: replace kitty tabs with an fzf picker
- **cli**: print coloured failures and warnings
- **cli**: add -f as the short flag for kill --force
- **cli**: configure the picker and restore session files
- **cli**: replace connect with attach and add scoped picking
- add Neovim Server Manager

### Fix

- **install**: warn when user namespaces are blocked
- **ci**: allow unprivileged user namespaces
- **install**: warn when fusermount is missing
- **cli**: reject an answer that is not a number
- **cli**: tell a busy server from a stopped one
- **cli**: harden the fzf picker
- **nix**: follow the Commitizen version
- **cli**: ignore a missing zoxide
- **nix**: name the packaged script nsm

### Refactor

- **cli**: list SSH hosts and split the store module
- **plugin**: start sessions asynchronously

### Perf

- **cli**: start the kill client with --clean
