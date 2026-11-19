{
  description = "Neovim Server Manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      versions = import ./nix/versions.nix;
      forAllSystems = nixpkgs.lib.genAttrs systems;

      perSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          outputs = import ./nix/lib.nix {
            inherit pkgs;
            root = self;
          };
          launchers = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
            pkgs.lib.mapAttrs' (name: package: pkgs.lib.nameValuePair "nsm-${name}" package) (
              pkgs.callPackage ./nix/launcher.nix {
                root = self;
                inherit versions;
              }
            )
          );
        in
        {
          packages = {
            default = outputs.packages.nsm;
            nsm = outputs.packages.nsm;
            neovim-plugin = outputs.packages.neovimPlugin;
          }
          // launchers;

          apps.default = {
            type = "app";
            program = "${outputs.packages.nsm}/bin/nsm";
            meta.description = "Run the nsm CLI";
          };
        };
      all = forAllSystems perSystem;
    in
    {
      packages = nixpkgs.lib.mapAttrs (_: output: output.packages) all;
      apps = nixpkgs.lib.mapAttrs (_: output: output.apps) all;
    };
}
