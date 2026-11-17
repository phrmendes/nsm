# Neovim Server Manager

Neovim Server Manager keeps one detached Neovim server per project. A picker in Neovim or in the terminal switches the current UI to a session with `:connect`, so the terminal keeps its window and its scrollback.

For full documentation, see [`:help nsm`](doc/nsm.txt).

## Features

- **One server per project** — start a headless Neovim for a directory and attach to it later.
- **Switch in place** — `:Nsm` opens a picker and reattaches the current UI. The terminal stays open.
- **Session picker** — sessions, the repositories below your project roots, and recent zoxide directories in one list.
- **Stop and start** — `:Nsm kill` stops a session and offers a force stop when it has unsaved buffers. `:Nsm new` starts a session for a directory.
- **Scope filter** — limit the picker to one directory with `--scope` or `NSM_SCOPE`.
- **Session restore** — run a project Vimscript file when a session starts.
- **Terminal parity** — the `nsm` command reads the same SQLite store.

## Installation

Install the `nsm` command, then the Neovim plugin. The command runs on Linux only.

### CLI

#### Nix

The flake ships the `nsm` command with `fzf` and `util-linux` on `PATH`:

```bash
nix run github:phrmendes/nsm -- list      # try it
nix profile install github:phrmendes/nsm  # install it
```

Or add the flake as an input and put the package in your profile:

```nix
inputs.nsm.url = "github:phrmendes/nsm";

home.packages = [ inputs.nsm.packages.${pkgs.system}.nsm ];
```

#### Script

For systems without Nix, install the command into `~/.local/bin` with the install script:

```bash
curl -fsSL https://github.com/phrmendes/nsm/releases/latest/download/install.sh | sh
```

The script downloads the AppImage of the latest release, checks its checksum, and installs it as `~/.local/bin/nsm`. The AppImage holds Nushell, `fzf` and `util-linux`, so you need Neovim and `git` on the host. It needs `/dev/fuse`. Without it, run `nsm` with `APPIMAGE_EXTRACT_AND_RUN=1`, which is slower.

Pin a version with `NSM_VERSION=0.2.0`, and change the directory with `NSM_INSTALL_DIR`:

```bash
curl -fsSL https://github.com/phrmendes/nsm/releases/download/v0.2.0/install.sh | NSM_VERSION=0.2.0 sh
```

### Plugin

With [vim.pack](https://neovim.io/doc/user/usr_05.html#vim.pack) (Neovim 0.12+):

```lua
vim.pack.add({ "https://github.com/phrmendes/nsm" })
```

#### Install the CLI on update

Without Nix, you can let `vim.pack` run the install script each time it installs or updates the plugin. Add this autocmd before `vim.pack.add`:

```lua
vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    if ev.data.spec.name ~= "nsm" or ev.data.kind == "delete" then
      return
    end

    vim.system({ "sh", vim.fs.joinpath(ev.data.path, "scripts", "install.sh") })
  end,
})
```

The script asks nothing. It also warns when Neovim or `/dev/fuse` is missing. Nix users do not need this hook, because the Nix package already ships the command.

## Quick start

```lua
require("nsm").setup({ keymap = "<leader>w" })
```

Set your project roots in `~/.config/.nsm.nuon`:

```nuon
{
  projects: ["~/Projects", "/mnt/external/projects"]
  icons: { running: "🟢", busy: "🟡", stored: "⚫", directory: "📁" }
  restore: { file: "Session.vim" }
}
```

Omit `projects` to disable repository discovery. `restore.file` runs project Vimscript, so enable it only for trusted projects.

## Usage

| Command            | Description                     |
| ------------------ | ------------------------------- |
| `:Nsm`             | Pick a session and switch to it |
| `:Nsm new`         | Start a session for a directory |
| `:Nsm kill`        | Stop a chosen session           |
| `:checkhealth nsm` | Verify installation             |

The plugin also sets `<Plug>(nsm-switch)`, `<Plug>(nsm-kill)` and `<Plug>(nsm-new)`. `setup({ keymap = "<leader>s" })` changes the mapping, and `keymap = false` removes it.

From Lua:

```lua
require("nsm").switch()         -- pick a session and switch to it
require("nsm").new()            -- start a session for a directory
require("nsm").kill()           -- pick a session and stop it
require("nsm").connect(address) -- attach to the server at address
```

From the terminal:

| Command                          | Description                                   |
| -------------------------------- | --------------------------------------------- |
| `nsm attach [name-or-directory]` | Create or open a session, or pick one         |
| `nsm switch`                     | Pick another session                          |
| `nsm last`                       | Return to the previous session                |
| `nsm new <name> [path]`          | Create a named session                        |
| `nsm start <name-or-directory>`  | Start a session and print its socket          |
| `nsm list`                       | Print sessions as a table                     |
| `nsm pick`                       | Print the picker rows as JSON                 |
| `nsm kill [name]`                | Stop a session, or every session with `--all` |

## Requirements

- Linux on x86_64
- Neovim 0.12+
- The `nsm` command: the Nix package and the AppImage bundle Nushell, `fzf` and `util-linux`
- `git` on `PATH` to name a session after its repository root. Without `git`, a session takes the directory name

### Optional

- [zoxide](https://github.com/ajeetdsouza/zoxide) — recent directories in the picker

## Development

This project uses [devenv](https://devenv.sh).

```bash
devenv test              # run the CLI and plugin tests
devenv tasks run doc:run # regenerate doc/nsm.txt
```

Commits follow [Conventional Commits](https://www.conventionalcommits.org). Each push to `main` bumps the version from them, and the workflow publishes the AppImage and `install.sh` for the new tag. A manual run of the workflow republishes a release whose tag already exists.

`nix flake check` runs the tests, the lint, the format check, and builds the AppImage. The workflow runs it on every push and pull request.

## License

Apache-2.0. See [LICENSE](LICENSE).
