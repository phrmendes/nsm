# Neovim Server Manager

Keep one detached Neovim server per project. Pick and switch sessions from Neovim or the terminal.

## Install

```lua
vim.pack.add({ "https://github.com/phrmendes/nsm" })
```

```bash
nix build .#nsm
export PATH="$(nix build --print-out-paths .#nsm)/bin:$PATH"
```

## Setup

`:Nsm` uses `<leader>w` by default. Change it with:

```lua
require("nsm").setup({ keymap = "<leader>s" })
```

Hosts from `~/.ssh/config` also appear in the picker when Neovim supports `:connect ssh://`.

Run `:checkhealth nsm`. See `:help nsm` for commands, configuration, and requirements.

## License

Apache-2.0. See [LICENSE](LICENSE).
