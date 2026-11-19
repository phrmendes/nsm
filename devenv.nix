{ pkgs, ... }:
{
  languages.go.enable = true;

  languages.lua = {
    enable = true;
    package = pkgs.luajit;
    lsp.package = pkgs.lua-language-server;
  };

  packages = with pkgs; [
    commitizen
    git
    neovim
    nu-lint
    nufmt
    nushell
    perl
    shellcheck
    stylua
    util-linux
  ];

  env = {
    NU_LIB_DIRS = toString ./cli;
    MINI_NVIM = "${pkgs.vimPlugins.mini-nvim}";
  };

  enterTest = "nu scripts/test.nu";

  git-hooks.hooks = {
    nufmt.enable = true;
    stylua.enable = true;
    gofmt.enable = true;
    commitizen = {
      enable = true;
      name = "commitizen";
      entry = "${pkgs.commitizen}/bin/cz check --commit-msg-file";
      language = "system";
      stages = [ "commit-msg" ];
    };
    nu-lint = {
      enable = true;
      settings.configPath = ./nu-lint.toml;
    };
    shellcheck = {
      enable = true;
      excludes = [ "^\\.envrc$" ];
    };
    docs = {
      enable = true;
      name = "docs";
      entry = "${pkgs.coreutils}/bin/env MINI_NVIM=${pkgs.vimPlugins.mini-nvim} ${pkgs.neovim}/bin/nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniDoc.generate(nil, \"doc/nsm.txt\")' -c 'qa!'";
      files = "^lua/";
      pass_filenames = false;
      language = "system";
    };
  };
}
