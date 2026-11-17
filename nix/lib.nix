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
}
