{
  lib,
  stdenvNoCC,
  fetchurl,
  writeTextFile,
  shellcheck,
  squashfsTools,
  pkgsStatic,
  root,
  runtime,
}:

let
  nuVersion = "0.116.1";

  script =
    name: text:
    writeTextFile {
      inherit name text;
      executable = true;
      checkPhase = "${lib.getExe shellcheck} $target";
    };

  appRun = script "AppRun" /* bash */ ''
    #!/bin/sh
    unset CDPATH
    HERE=$(cd -- "$(dirname -- "$0")" && pwd)
    export PATH="$HERE/usr/bin:$PATH"
    export NU_LIB_DIRS="$HERE/usr/share/nsm/cli"
    exec "$HERE/usr/bin/nsm" "$@"
  '';

  nsmShim = script "nsm" /* bash */ ''
    #!/bin/sh
    unset CDPATH
    HERE=$(cd -- "$(dirname -- "$0")" && pwd)
    exec "$HERE/nu" --no-config-file "$NU_LIB_DIRS/main.nu" "$@"
  '';

  programs = {
    fzf = lib.getExe pkgsStatic.fzf;
    setsid = lib.getExe' pkgsStatic.util-linuxMinimal "setsid";
    timeout = lib.getExe' pkgsStatic.coreutils "timeout";
  };

  appdir = stdenvNoCC.mkDerivation {
    name = "nsm-appdir";

    src = fetchurl {
      url = "https://github.com/nushell/nushell/releases/download/${nuVersion}/nu-${nuVersion}-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-E+913wjfMPjXsDHfU46CpSxudM6DmxqQkcOj8ZacN0I=";
    };

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      install -Dm755 nu $out/usr/bin/nu

      ${lib.concatMapStrings (name: ''
        install -Dm755 ${programs.${name}} $out/usr/bin/${name}
      '') (lib.attrNames programs)}

      install -Dm755 ${nsmShim} $out/usr/bin/nsm
      install -Dm755 ${appRun} $out/AppRun

      mkdir -p $out/usr/share/nsm
      cp -r ${root}/cli $out/usr/share/nsm/cli
    '';
  };

  image = stdenvNoCC.mkDerivation {
    name = "nsm.AppImage";

    dontUnpack = true;
    nativeBuildInputs = [ squashfsTools ];

    installPhase = ''
      offset=$(stat -L -c%s ${runtime})
      mksquashfs ${appdir} $out -comp zstd -Xcompression-level 19 -b 1M -offset "$offset" -all-root -noappend -quiet
      dd if=${runtime} of=$out conv=notrunc status=none
      chmod 755 $out
    '';

    meta = {
      platforms = [ "x86_64-linux" ];
      mainProgram = "nsm";
    };
  };
in
{
  inherit appdir image;
}
