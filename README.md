# Neovim Server Manager

Neovim Server Manager keeps detached Neovim servers for project workspaces. It stores each server's name, project path, and socket in SQLite.

## Requirements

- `nvim` and `git`.
- Nushell with the skim plugin, which provides `sk` for the picker. Install `nu_plugin_skim`, then run `plugin add nu_plugin_skim` and `plugin use nu_plugin_skim`.
- `zoxide` for directory discovery in the picker.
- `kitty` is optional. It adds one tab per session.

The flake bundles Nushell with the skim plugin. The packaged `nsm` still needs `nvim` on `PATH`.

## Commands

- `nsm attach <name-or-directory>` creates or opens a session.
- `nsm attach` opens the session picker.
- `nsm switch` opens the picker without the current session.
- `nsm attach [name]` opens an existing session. Add `--create` to create it when missing.
- `nsm last` returns to the previously attached session.
- `nsm new <name> [path]` creates a named session.
- `nsm list` prints sessions as a table.
- `nsm kill [name]` stops a session. Without a name, it opens the session picker. Add `--all` to stop every session. It refuses to stop sessions that have unsaved buffers, unless you pass `--force`.

The picker opens in the lower half of the terminal. To list only sessions under one directory, set `NSM_SCOPE=/path/to/folder` or pass `--scope /path/to/folder` to `attach`, `switch`, or `kill`.

Inside kitty, nsm opens one tab per session and focuses an existing tab. Run `:detach` in Neovim to detach the UI and keep the server running. Outside kitty, use `--here` to attach in the current terminal. `:detach` is the safe exit, because the server keeps its buffers. `nsm kill` stops the server and loses unsaved changes.

## Neovim plugin

The plugin registers `:Nsm`, the `<Plug>(nsm-switch)` mapping, and a default `<leader>w` mapping to it for the kitty overlay session picker. All of them load the module only when you use them. Add this project to Neovim's runtime path, or use the `neovim-plugin` package output from this flake.

To choose your own keys:

```lua
vim.keymap.set("n", "<leader>s", "<Plug>(nsm-switch)")
```

Pass options to `setup()` to change the default map:

```lua
require("nsm").setup({ keymap = "<leader>s" })
require("nsm").setup({ keymap = false }) -- no mapping
```

The picker previews a running session by calling `buffers()` from this plugin. A running server without the plugin shows a message instead of its buffers.

Run `:checkhealth nsm` to check the `nsm` and `kitten` executables and `KITTY_LISTEN_ON`. The help file is `doc/nsm.txt`, generated from the Lua annotations with `devenv tasks run doc:run` after you change them.

## Nix

Build the CLI with `nix build .#nsm`. Build the plugin with `nix build .#neovim-plugin`. The default package is nsm.

## Development

Enter the environment with `direnv allow` or `devenv shell`. It provides `stylua` and `lua-language-server` for Lua, and `nu-lint`, `nufmt`, and Nushell for the CLI. Run `devenv test` to run the Nushell and Lua test suites. Run `devenv tasks run lint:all` and `devenv tasks run format:check` before changes.
