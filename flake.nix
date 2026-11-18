{
  description = "Neovim Server Manager";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.nix-appimage = {
    url = "github:ralismark/nix-appimage";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-appimage,
    }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      perSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          appimage = pkgs.callPackage ./nix/appimage.nix {
            root = self;
            runtime = nix-appimage.appimage-runtimes.${system}.appimage-type2-runtime;
          };
          outputs = import ./nix/lib.nix {
            inherit pkgs;
            root = self;
          };
        in
        {
          packages = {
            default = outputs.packages.nsm;
            nsm = outputs.packages.nsm;
            neovim-plugin = outputs.packages.neovimPlugin;
            nsm-appdir = appimage.appdir;
            nsm-appimage = appimage.image;
          };

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
