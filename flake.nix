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
            nsm-appimage = nix-appimage.lib.${system}.mkAppImage {
              program = pkgs.lib.getExe outputs.packages.nsm;
              runtime = nix-appimage.appimage-runtimes.${system}.appimagecrafters;
              squashfsArgs = [
                "-comp"
                "zstd"
                "-Xcompression-level"
                "19"
                "-b"
                "1M"
              ];
            };
          };

          apps.default = {
            type = "app";
            program = "${outputs.packages.nsm}/bin/nsm";
            meta.description = "Run the nsm CLI";
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
