{ pkgs, root }:

let
  inherit (pkgs) lib;

  nushell = pkgs.nushell.withPlugins [ pkgs.nushellPlugins.skim ];

  nsmScript = pkgs.writers.makeScriptWriter {
    interpreter = "${pkgs.coreutils}/bin/env -S NU_LIB_DIRS=${root}/cli ${lib.getExe nushell} --no-config-file";
  } "/bin/nsm" (builtins.readFile (root + "/cli/main.nu"));

  nsm = pkgs.symlinkJoin {
    name = "nsm";
    paths = [ nsmScript ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/nsm --prefix PATH : ${
        lib.makeBinPath [
          pkgs.git
          pkgs.kitty
          pkgs.util-linux
          pkgs.zoxide
        ]
      }
    '';
  };

  neovimPlugin = pkgs.vimUtils.buildVimPlugin {
    pname = "nsm.nvim";
    version = "0.1.0";
    src = root;
  };

  unitTests = pkgs.runCommand "nsm-unit-tests" {
    nativeBuildInputs = with pkgs; [
      nushell
      bash
      coreutils
      git
      neovim
    ];
    NU_LIB_DIRS = "${root}/cli";
    MINI_NVIM = "${pkgs.vimPlugins.mini-nvim}";
  } ''
    cd ${root}
    nu tests/cli/tests.nu
    nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniTest.run()'
    cp -r ${root}/lua ${root}/scripts $TMPDIR
    cd $TMPDIR
    nvim --headless --noplugin -u ./scripts/init.lua -c "lua MiniDoc.generate(nil, 'doc/nsm.txt')" -c 'qa!'
    diff -u ${root}/doc/nsm.txt $TMPDIR/doc/nsm.txt
    touch $out
  '';
in
{
  packages = {
    inherit nsm neovimPlugin;
  };

  checks = {
    unit = unitTests;
  };
}
