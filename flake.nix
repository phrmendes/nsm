{
  description = "Neovim Server Manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      perSystem = system:
        let
          pkgs = import nixpkgs { inherit system; };
          nushell = pkgs.nushell.withPlugins [ pkgs.nushellPlugins.skim ];
          nsmScript = pkgs.writers.makeScriptWriter {
            interpreter = "${pkgs.coreutils}/bin/env -S NU_LIB_DIRS=${./cli} ${pkgs.lib.getExe nushell} --no-config-file";
          } "/bin/nsm" (builtins.readFile ./cli/main.nu);
          nsm = pkgs.symlinkJoin {
            name = "nsm";
            paths = [ nsmScript ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/nsm --prefix PATH : ${pkgs.lib.makeBinPath [
                pkgs.git
                pkgs.kitty
                pkgs.util-linux
                pkgs.zoxide
              ]}
            '';
          };
          neovimPlugin = pkgs.vimUtils.buildVimPlugin {
            pname = "nsm.nvim";
            version = "0.1.0";
            src = self;
          };
          unitTests = pkgs.runCommand "nsm-unit-tests" {
            nativeBuildInputs = with pkgs; [
              nushell
              bash
              coreutils
              git
              neovim
            ];
            NU_LIB_DIRS = "${self}/cli";
            MINI_NVIM = "${pkgs.vimPlugins.mini-nvim}";
          } ''
            cd ${self}
            nu tests/cli/tests.nu
            nvim --headless --noplugin -u ./scripts/init.lua -c 'lua MiniTest.run()'
            cp -r ${self}/lua ${self}/scripts $TMPDIR
            cd $TMPDIR
            nvim --headless --noplugin -u ./scripts/init.lua -c "lua MiniDoc.generate(nil, 'doc/nsm.txt')" -c 'qa!'
            diff -u ${self}/doc/nsm.txt $TMPDIR/doc/nsm.txt
            touch $out
          '';
        in
        {
          inherit nsm neovimPlugin unitTests;
        };
    in
    {
      packages = forAllSystems (system:
        let outputs = perSystem system;
        in {
          default = outputs.nsm;
          nsm = outputs.nsm;
          neovim-plugin = outputs.neovimPlugin;
        });

      apps = forAllSystems (system:
        let outputs = perSystem system;
        in {
          default = {
            type = "app";
            program = "${outputs.nsm}/bin/nsm";
          };
        });

      checks = forAllSystems (system:
        let outputs = perSystem system;
        in {
          unit = outputs.unitTests;
        });
    };
}
