{ pkgs, root }:

let
  inherit (pkgs) lib;

  version = (builtins.fromTOML (builtins.readFile (root + "/.cz.toml"))).tool.commitizen.version;
in
{
  packages = {
    nsm = pkgs.writeTextFile {
      name = "nsm";
      destination = "/bin/nsm";
      executable = true;
      meta.license = lib.licenses.asl20;
      meta.mainProgram = "nsm";
      text =
        let
          binPath =
            with pkgs;
            lib.makeBinPath [
              fzf
              util-linuxMinimal
            ];
        in
        ''
          #!${pkgs.coreutils}/bin/env -S NU_LIB_DIRS=${root}/cli ${lib.getExe pkgs.nushell} --no-config-file
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
      meta.license = lib.licenses.asl20;
    };
  };

  checks.unit =
    pkgs.runCommand "nsm-unit-tests"
      {
        nativeBuildInputs = with pkgs; [
          nushell
          bash
          coreutils
          git
          neovim
          util-linux
        ];
        NU_LIB_DIRS = "${root}/cli";
        MINI_NVIM = "${pkgs.vimPlugins.mini-nvim}";
      }
      ''
        cd ${root}
        nu ${root}/scripts/test.nu
        cp -r ${root}/lua ${root}/scripts $TMPDIR
        cd $TMPDIR
        nvim --headless --noplugin -u ./scripts/init.lua -c "lua MiniDoc.generate(nil, 'doc/nsm.txt')" -c 'qa!'
        diff -u ${root}/doc/nsm.txt $TMPDIR/doc/nsm.txt
        touch $out
      '';

  checks.static =
    pkgs.runCommand "nsm-static-checks"
      {
        nativeBuildInputs = with pkgs; [
          nufmt
          nu-lint
          shellcheck
          stylua
        ];
        HOME = "$TMPDIR";
      }
      ''
        cd ${root}
        nufmt --dry-run cli tests
        stylua --check lua plugin scripts tests
        nu-lint --format compact --config nu-lint.toml cli tests
        shellcheck scripts/install.sh
        touch $out
      '';
}
