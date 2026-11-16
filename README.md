# Neovim Server Manager

Keep one detached Neovim server per project, and switch between them from Neovim or the terminal. Sessions live in SQLite and each server listens on a socket.

For full documentation, see [`:help nsm`](doc/nsm.txt).

## Features

- **Detached servers** — one headless Neovim per project keeps buffers and editor state alive.
- **Picker** — fzf in the terminal and `vim.ui.select` in Neovim, over sessions, zoxide directories, and Git repositories under configured project roots. The top five zoxide paths use a `[Z]` label. The terminal picker also shows a file preview.
- **In-place switch** — `:Nsm` reattaches the current UI to the chosen session with `:connect`.
- **Scope** — limit the picker to one folder with `--scope` or `NSM_SCOPE`.
- **Safe exits** — `:detach` keeps the server, `nsm kill` stops it, and unsaved buffers block the stop.

## Installation

With [vim.pack](https://neovim.io/doc/user/usr_05.html#vim.pack) (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/phrmendes/nsm" })
```

Install the `nsm` CLI and put it on `PATH`. From this repository:

```bash
nix build .#nsm
export PATH="$(nix build --print-out-paths .#nsm)/bin:$PATH"
```

## Setup

The plugin registers `:Nsm`, the `<Plug>(nsm-switch)` mapping, and a default `<leader>w` mapping to `:Nsm`. All of them load the module only when you use them.

`:Nsm` opens a `vim.ui.select` picker and switches the current UI to the chosen session with `:connect`.

Choose your own key with the `<Plug>` mapping:

```lua
vim.keymap.set("n", "<leader>s", "<Plug>(nsm-switch)")
```

Or change the default map with `setup()`:

```lua
require("nsm").setup({ keymap = "<leader>s" })
require("nsm").setup({ keymap = false }) -- no mapping
```

Run `:checkhealth nsm` to check the `nsm` executable.

## Usage

| Command                                   | Description                                                  |
| ----------------------------------------- | ------------------------------------------------------------ |
| `nsm attach [name-or-directory]`          | Create or open a session, or pick one                        |
| `nsm switch`                              | Pick another session, without the current one                |
| `nsm last`                                | Return to the previous session                               |
| `nsm new <name> [path]`                   | Create a named session                                       |
| `nsm start <name-or-directory>`           | Start a session and print its socket                         |
| `nsm list`                                | Print sessions as a table                                    |
| `nsm pick`                                | Print the picker rows as JSON, for the plugin                |
| `nsm kill [name]`                         | Stop a session, or every session with `--all`                |
| `nsm a`, `nsm s`, `nsm l`, `nsm n`, `nsm ls`, `nsm k` | Short forms of the commands above               |

The CLI picker opens in the lower half of the terminal. To list only sessions under one directory, pass `--scope /path/to/folder` to `attach`, `switch`, or `kill`, or set `NSM_SCOPE=/path/to/folder`.

`nsm kill` refuses to stop a session that has unsaved buffers. Pass `--force` (`-f`), or use `--all --force` to stop everything.

nsm opens the UI of a session in the current terminal. `:Nsm` reattaches the current UI to the chosen session and leaves the server of the previous session running. Run `:detach` in Neovim to detach the UI and keep the server running. `:detach` is the safe exit, because the server keeps its buffers. `nsm kill` stops the server and loses unsaved changes.

## Configuration

Create `~/.config/.nsm.nuon` to set the default projects folder and the picker icons:

```nuon
{
  projects: ["~/Projects", "/mnt/external/projects"]
  icons: { running: "🟢", stored: "⚫", directory: "📁" }
  restore: { file: "Session.vim" }
}
```

The `projects` list in this file defines all project roots. Nsm does not read project roots from environment variables. Omit `projects` to disable Git repository discovery. Omit an icon key to keep its default. A malformed file fails with its path.

`restore.file` is optional. When it is set and the file exists in the project, nsm starts the server with `nvim ... -S <file>`. nsm does not create the file. Use `:mksession` in the project to write one. The file runs project Vimscript, so only enable it for projects you trust.

## Requirements

- Neovim 0.12+
- `nsm` on `PATH`, plus `nvim` and `git`
- `fzf` and `zoxide` on `PATH`

The packaged `nsm` includes Nushell and fzf. It still needs `nvim` on `PATH`.

## Commits

Use Conventional Commits: `type(scope)!: summary`, then one short paragraph that explains why. A `commit-msg` hook installed by devenv runs `cz check`, so enter the environment once with `devenv shell` or `direnv allow` before committing.

## Releases

Commitizen owns the version and the changelog. The version lives in `.cz.toml`.

```bash
cz changelog     # print the changelog for the next release
cz bump --yes    # bump the version, update CHANGELOG.md, and tag
```

## Development

This project uses [devenv](https://devenv.sh).

```bash
devenv test                    # run the Nushell and plugin test suites
devenv tasks run doc:run       # regenerate doc/nsm.txt
devenv tasks run lint:all      # lint the Nushell code
devenv tasks run format:check
```

The `nsm` CLI lives in `cli/` and the plugin in `lua/nsm/`. Build the plugin with `nix build .#neovim-plugin`.
