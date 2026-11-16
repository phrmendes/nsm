{
  description = "Neovim Server Manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      perSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          outputs = import ./nix/lib.nix { inherit pkgs; root = self; };
        in
        {
          packages = {
            default = outputs.packages.nsm;
            nsm = outputs.packages.nsm;
            neovim-plugin = outputs.packages.neovimPlugin;
          };

          apps.default = {
            type = "app";
            program = "${outputs.packages.nsm}/bin/nsm";
          };

          checks = outputs.checks;
        };
    in
    {
      packages = forAllSystems (system: (perSystem system).packages);
      apps = forAllSystems (system: (perSystem system).apps);
      checks = forAllSystems (system: (perSystem system).checks);
    };
}
