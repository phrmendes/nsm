{ pkgs, ... }:
{
  languages.lua = {
    enable = true;
    package = pkgs.luajit;
    lsp.package = pkgs.lua-language-server;
  };

  packages = with pkgs; [
    commitizen
    fzf
    git
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

  git-hooks.hooks.commitizen = {
    enable = true;
    name = "commitizen";
    entry = "${pkgs.commitizen}/bin/cz check --commit-msg-file";
    language = "system";
    stages = [ "commit-msg" ];
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
