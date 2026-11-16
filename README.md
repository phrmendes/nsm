# Neovim Server Manager

Keep one detached Neovim server per project, and switch between them from Neovim or the terminal. Sessions live in SQLite and each server listens on a socket.

For full documentation, see [`:help nsm`](doc/nsm.txt).

## Features

- **Detached servers** — one headless Neovim per project keeps buffers and editor state alive.
- **Picker** — fuzzy search over sessions, zoxide directories, and Git repositories under `PROJECTS_DIR`, with an icon per kind and a file preview.
- **Kitty tabs** — one tab per session, with an overlay picker from Neovim.
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

The plugin registers `:Nsm`, the `<Plug>(nsm-switch)` mapping, and a default `<leader>w` mapping to it. All of them load the module only when you use them.

Choose your own keys with the `<Plug>` mapping:

```lua
vim.keymap.set("n", "<leader>s", "<Plug>(nsm-switch)")
```

Or change the default map with `setup()`:

```lua
require("nsm").setup({ keymap = "<leader>s" })
require("nsm").setup({ keymap = false }) -- no mapping
```

Inside kitty, `:Nsm` and the mapping open the picker in an overlay. Run `:checkhealth nsm` to check the `nsm` and `kitten` executables and `KITTY_LISTEN_ON`.

## Usage

| Command                                   | Description                                                  |
| ----------------------------------------- | ------------------------------------------------------------ |
| `nsm attach [name-or-directory]`          | Create or open a session, or pick one                        |
| `nsm switch`                              | Pick another session, without the current one                |
| `nsm last`                                | Return to the previous session                               |
| `nsm new <name> [path]`                   | Create a named session                                       |
| `nsm list`                                | Print sessions as a table                                    |
| `nsm kill [name]`                         | Stop a session, or every session with `--all`                |
| `nsm a`, `nsm s`, `nsm l`, `nsm n`, `nsm ls`, `nsm k` | Short forms of the commands above               |

The picker opens in the lower half of the terminal. To list only sessions under one directory, pass `--scope /path/to/folder` to `attach`, `switch`, or `kill`, or set `NSM_SCOPE=/path/to/folder`.

`nsm kill` refuses to stop a session that has unsaved buffers. Pass `--force` (`-f`), or use `--all --force` to stop everything.

Inside kitty, nsm opens one tab per session and focuses an existing tab. Run `:detach` in Neovim to detach the UI and keep the server running. Outside kitty, use `--here` to attach in the current terminal. `:detach` is the safe exit, because the server keeps its buffers. `nsm kill` stops the server and loses unsaved changes.

## Configuration

Create `~/.config/.nsm.nuon` to set the default projects folder and the picker icons:

```nuon
{
  projects: { dir: "~/Projects" }
  icons: { running: "🟢", stored: "⚫", directory: "📁" }
  restore: { file: "Session.vim" }
}
```

`PROJECTS_DIR` still wins over `projects.dir`. Environment variables take precedence over the file. Omit a key to keep its default. A malformed file fails with its path.

`restore.file` is optional. When it is set and the file exists in the project, nsm starts the server with `nvim ... -S <file>`. nsm does not create the file. Use `:mksession` in the project to write one. The file runs project Vimscript, so only enable it for projects you trust.

## Requirements

- Neovim 0.12+
- `nsm` on `PATH`, plus `nvim` and `git`
- Nushell with the skim plugin, which provides `sk`. Install `nu_plugin_skim`, then run `plugin add nu_plugin_skim` and `plugin use nu_plugin_skim`
- `zoxide` for directory discovery

### Optional

- `kitty` for tabs and the overlay picker

The flake bundles Nushell with the skim plugin. The packaged `nsm` still needs `nvim` on `PATH`.

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
