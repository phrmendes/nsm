{ pkgs, root }:

let
  inherit (pkgs) lib;

  nushell = pkgs.nushell;
  versionLine = lib.findFirst (line: lib.hasPrefix "version" line) "" (
    lib.splitString "\n" (builtins.readFile (root + "/.cz.toml"))
  );
  version = lib.removeSuffix "\"" (lib.removePrefix "version = \"" (lib.trim versionLine));
in
{
  packages = {
    nsm = pkgs.writeTextFile {
      name = "nsm";
      destination = "/bin/nsm";
      executable = true;
      text =
        let
          binPath = with pkgs; lib.makeBinPath [ fzf git util-linux zoxide ];
        in
        ''
          #!${pkgs.coreutils}/bin/env -S NU_LIB_DIRS=${root}/cli ${lib.getExe nushell} --no-config-file
          ${builtins.readFile (root + "/cli/main.nu")}

          $env.PATH = ($env.PATH | prepend [${
            lib.concatMapStrings (path: " \"${path}\"") (lib.splitString ":" binPath)
          }])
        '';
    };

    neovimPlugin = pkgs.vimUtils.buildVimPlugin {
      pname = "nsm.nvim";
      inherit version;
      src = root;
    };
  };

  checks.unit = pkgs.runCommand "nsm-unit-tests" {
    nativeBuildInputs = with pkgs; [
      nushell
      fzf
      bash
      commitizen
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
}
