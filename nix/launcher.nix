{
  lib,
  stdenvNoCC,
  buildGoModule,
  fetchurl,
  runCommand,
  procps,
  root,
  versions,
}:

let
  version = (builtins.fromTOML (builtins.readFile (root + "/.cz.toml"))).tool.commitizen.version;

  release = system: "https://github.com/nushell/nushell/releases/download/${versions.nu}/nu-${versions.nu}-${system}.tar.gz";

  targets = {
    linux-x86_64 = {
      goos = "linux";
      goarch = "amd64";
      magic = "7f454c46";
      nu = {
        slug = "x86_64-unknown-linux-musl";
        hash = "sha256-E+913wjfMPjXsDHfU46CpSxudM6DmxqQkcOj8ZacN0I=";
      };
    };
    darwin-arm64 = {
      goos = "darwin";
      goarch = "arm64";
      magic = "cffaedfe";
      nu = {
        slug = "aarch64-apple-darwin";
        hash = "sha256-MC+z38XUTn/g1bgie+jnW0w5VsqNSAQjTlxo+90+SRc=";
      };
    };
    darwin-x86_64 = {
      goos = "darwin";
      goarch = "amd64";
      magic = "cffaedfe";
      nu = {
        slug = "x86_64-apple-darwin";
        hash = "sha256-RDBvB2byvg52PQx6amd0U3WJozV5ehmdjltHPXZuxr0=";
      };
    };
  };

  mkBundle =
    name: target:
    stdenvNoCC.mkDerivation {
      name = "nsm-bundle-${name}.tar.gz";

      src = fetchurl {
        url = release target.nu.slug;
        inherit (target.nu) hash;
      };

      dontConfigure = true;
      dontBuild = true;
      dontFixup = true;

      installPhase = ''
        mkdir -p bundle/bin bundle/share/nsm
        tar -xzf $src --strip-components=1 -C bundle/bin --wildcards '*/nu'
        cp -r --no-preserve=mode ${root}/cli bundle/share/nsm/cli
        tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C bundle -c . | gzip -n > $out
      '';
    };

  mkLauncher =
    name: target:
    let
      bundle = mkBundle name target;
      id = builtins.substring 11 16 (builtins.unsafeDiscardStringContext (builtins.baseNameOf bundle));

      binary = buildGoModule {
        pname = "nsm-${name}";
        inherit version;
        src = root + "/launcher";
        vendorHash = null;
        doCheck = target.goos == "linux";
        nativeCheckInputs = [ procps ];
        buildFlags = [ "-trimpath" ];

        tags = [ "bundle" ];
        ldflags = [
          "-s"
          "-w"
          "-X main.bundleID=${id}"
        ];

        env.CGO_ENABLED = "0";

        preBuild = ''
          export GOOS=${target.goos} GOARCH=${target.goarch}
          cp ${bundle} bundle.tar.gz
        '';

        postInstall = ''
          if [ -d $out/bin/${target.goos}_${target.goarch} ]; then
            mv $out/bin/${target.goos}_${target.goarch}/* $out/bin/
            rmdir $out/bin/${target.goos}_${target.goarch}
          fi
        '';
      };
    in
    runCommand "nsm-${name}" { meta.platforms = lib.platforms.all; } ''
      magic=$(od -An -N4 -tx1 ${binary}/bin/launcher | tr -d ' \n')
      if [ "$magic" != "${target.magic}" ]; then
        echo "The file for ${name} starts with $magic, and not with ${target.magic}." >&2
        exit 1
      fi
      install -m755 ${binary}/bin/launcher $out
    '';
in
lib.mapAttrs mkLauncher targets
