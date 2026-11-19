# Neovim Server Manager

Neovim Server Manager keeps one detached Neovim server per project. A picker in Neovim or in the terminal switches the current UI to a session with `:connect`. The terminal keeps its window and its scrollback.

For full documentation, see [`:help nsm`](doc/nsm.txt).

## Features

- **One server per project** — start a headless Neovim for a directory and attach to it later.
- **Switch in place** — `:Nsm` opens a picker and reattaches the current UI. The terminal stays open.
- **Session picker** — sessions, the repositories below your project roots, and recent zoxide directories in one list. The terminal picker opens at once and adds rows as they load. In Neovim, the plugin uses `vim.ui.select`, so your picker plugin shows the list.
- **Stop and start** — `:Nsm kill` stops a session and offers a force stop when it has unsaved buffers. `:Nsm new` starts a session for a directory.
- **Scope filter** — limit the picker to one directory with `--scope` or `NSM_SCOPE`.
- **Session restore** — run a project Vimscript file when a session starts.
- **Project environment** — start each server inside the direnv or devenv environment of its project.

## Installation

Install the `nsm` command, then the Neovim plugin. The command runs on Linux (x86_64) and on macOS 15 or newer (Apple Silicon and Intel).

### CLI

#### Nix

The flake ships the `nsm` command with `util-linux` on `PATH`:

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

It downloads the file of your system from the latest release, checks its checksum, and installs it as `~/.local/bin/nsm`. The file bundles Nushell, `setsid` and `timeout`, and unpacks them into your cache folder on the first run (`~/.cache/nsm` on Linux, `~/Library/Caches/nsm` on macOS). You need Neovim, `bash` and `git` on the host. The installer verifies the signature of the release with `ssh-keygen`, which comes with OpenSSH, and it checks the checksum of the file. To install another version, put its tag in the URL:

```bash
curl -fsSL https://github.com/phrmendes/nsm/releases/download/vX.Y.Z/install.sh | sh
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

Nix users do not need this hook, because the Nix package already ships the command.

## Quick start

```lua
require("nsm").setup({ keymap = "<leader>w" })
```

Set your project roots in `~/.config/.nsm.nuon`:

```nuon
{
  projects: ["~/Projects", "/mnt/external/projects"]
  icons: { running: "🟢", stored: "⚫", directory: "📁" }
  restore: { file: "Session.vim" }
  start: { environment: true, timeout: 300 }
}
```

Omit `projects` to disable repository discovery. `restore.file` runs project Vimscript, so enable it only for trusted projects.

A server starts inside the environment of its project. A `.envrc` loads through `direnv exec`. A `devenv.nix` without a `.envrc` loads through `devenv shell --`. If the environment does not load, `nsm start` fails with the message of the tool, for example to run `direnv allow`. Set `start.environment` to `false` to skip it, and `start.timeout` to change the wait in seconds for a cold environment. While it loads, `nsm start` reports every 5 seconds. The plugin shows these messages when a start takes more than 100 ms.

## Usage

| Command            | Description                     |
| ------------------ | ------------------------------- |
| `:Nsm`             | Pick a session and switch to it |
| `:Nsm last`        | Switch to the previous session  |
| `:Nsm new`         | Start a session for a directory |
| `:Nsm kill`        | Stop a chosen session           |
| `:checkhealth nsm` | Verify installation             |

The plugin also sets `<Plug>(nsm-switch)`, `<Plug>(nsm-last)`, `<Plug>(nsm-kill)` and `<Plug>(nsm-new)`. `setup({ keymap = "<leader>s" })` maps a key to `<Plug>(nsm-switch)`, and `keymap = false` removes it.

From Lua:

```lua
require("nsm").switch()         -- pick a session and switch to it
require("nsm").last()           -- switch to the previous session
require("nsm").current()        -- the name of this session, or nil
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
| `nsm list`                       | Print sessions and their status               |
| `nsm pick`                       | Print the picker rows as JSON                 |
| `nsm kill [name]`                | Stop a session, or every session with `--all` |
| `nsm names`                      | Print the session names, one per line         |
| `nsm completions <shell>`        | Print the completion script of a shell        |
| `nsm --version`                  | Print the version                             |

`nsm list --json` prints the sessions as JSON for scripts. `nsm last --print` prints the socket of the previous session and does not open it.

### Statusline

`require("nsm").current()` returns the session name, so a statusline can show it:

```lua
vim.o.statusline = "%f %=%{v:lua.require('nsm').current()}"
```

### Shell completion

The scripts complete the commands, the session names, and directories.

```bash
eval "$(nsm completions bash)"  # bash: add it to ~/.bashrc
eval "$(nsm completions zsh)"   # zsh: add it to ~/.zshrc, after compinit
nsm completions nu | save --force ~/.config/nushell/nsm.nu  # Nushell: then add `source nsm.nu` to your config
```

## Requirements

- Linux on x86_64, or macOS 15 or newer on Apple Silicon or Intel
- Neovim 0.12+
- The `nsm` command: the Nix package and the release file bundle Nushell, `setsid` and `timeout`
- `bash` on `PATH` to start the server
- `git` on `PATH` to name a session after its repository root. Without `git`, a session takes the directory name
- A cache folder that allows programs to run. The release file unpacks Nushell there on the first run

### Optional

- [zoxide](https://github.com/ajeetdsouza/zoxide) — recent directories in the picker
- [direnv](https://direnv.net) or [devenv](https://devenv.sh) — the environment of a project that has a `.envrc` or a `devenv.nix`

## Development

This project uses [devenv](https://devenv.sh).

```bash
devenv test # run the hooks and the tests
```

The `docs` hook regenerates `doc/nsm.txt` when you commit a change in `lua/`.

## License

Apache-2.0. See [LICENSE](LICENSE).
