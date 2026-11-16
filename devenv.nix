{ pkgs, ... }:
let
  nushell = pkgs.nushell.withPlugins [ pkgs.nushellPlugins.skim ];
in
{
  languages.lua = {
    enable = true;
    package = pkgs.luajit;
    lsp.package = pkgs.lua-language-server;
  };

  packages = with pkgs; [
    git
    kitty
    neovim
    nu-lint
    nufmt
    nushell
    stylua
    util-linux
    zoxide
  ];

  env = {
    NU_LIB_DIRS = toString ./cli;
    MINI_NVIM = "${pkgs.vimPlugins.mini-nvim}";
  };

  enterTest = ''
    nu tests/cli/tests.nu
    nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniTest.run()'
  '';

  tasks = {
    "lint:all".exec = "nu-lint --format compact --config nu-lint.toml cli tests";
    "format:check".exec = "nufmt --dry-run cli tests && stylua --check lua plugin scripts tests";
    "doc:run".exec = "nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniDoc.generate()' -c 'qa!'";
  };
}
