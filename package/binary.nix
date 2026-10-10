# Extract and package a ZSF binary release
{
  pkgs,
  lib,
  stdenvNoCC,
  callPackage,
  coreutils,
  xcbuild,
  zigSource,
  zigVersion,
  zls,
}: let
  zig = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "zig";
    version = zigVersion;
    meta = import ./meta.nix {
      inherit lib;
      version = finalAttrs.version;
      date = zigSource._date or null;
    };
    passthru = {
      inherit zls;
      fetchDeps = callPackage ./fetch-deps.nix {inherit zig;};

      makePackage = {
        stdenv ? stdenvNoCC,
        src,
        depsHash ? lib.fakeHash,
        nativeBuildInputs ? [],
        ...
      } @ args:
        stdenv.mkDerivation (final:
          {
            inherit src;
            zigDeps = args.zigDeps or finalAttrs.passthru.fetchDeps {
              inherit (final) src;
              name = final.name or null;
              pname = final.pname or null;
              version = final.version or null;
              hash = depsHash;
            };
            nativeBuildInputs = nativeBuildInputs ++ [zig];

            postConfigure = ''
              ln -s ${final.zigDeps} "$ZIG_GLOBAL_CACHE_DIR/p"
            '';
          }
          // lib.removeAttrs args ["stdenv" "nativeBuildInputs" "depsHash"]);
    };

    src = zigSource;

    # xcbuild provides xcode-select, which is required for SDK detection on macos
    buildInputs = lib.optional stdenvNoCC.hostPlatform.isDarwin xcbuild;
    propagatedBuildInputs = lib.optional stdenvNoCC.hostPlatform.isDarwin xcbuild;

    env = {
      # This zig_default_optimize_flag below is meant to avoid CPU feature impurity in
      # Nixpkgs. However, this flagset is "unstable": it is specifically meant to
      # be controlled by the upstream development team - being up to that team
      # exposing or not that flags to the outside (especially the package manager
      # teams).

      # Because of this hurdle, @andrewrk from Zig Software Foundation proposed
      # some solutions for this issue. Hopefully they will be implemented in
      # future releases of Zig. When this happens, this flagset should be
      # revisited accordingly.

      # Below are some useful links describing the discovery process of this 'bug'
      # in Nixpkgs:

      # https://github.com/NixOS/nixpkgs/issues/169461
      # https://github.com/NixOS/nixpkgs/issues/185644
      # https://github.com/NixOS/nixpkgs/pull/197046
      # https://github.com/NixOS/nixpkgs/pull/241741#issuecomment-1624227485
      # https://github.com/ziglang/zig/issues/14281#issuecomment-1624220653
      zig_default_cpu_flag = "-Dcpu=baseline";

      zig_default_optimize_flag = "--release=safe";
    };

    setupHook = pkgs.zig_0_17.setupHook;

    postPatch =
      # Zig's build looks at /usr/bin/env to find dynamic linking info. This doesn't
      # work in Nix's sandbox. Use env from our coreutils instead.
      ''
        substituteInPlace lib/std/zig/system.zig \
          --replace "/usr/bin/env" "${lib.getExe' coreutils "env"}"
      ''
      # Zig tries to access xcrun and xcode-select at the absolute system path to query the macOS SDK
      # location, which does not work in the darwin sandbox.
      # Upstream issue: https://github.com/ziglang/zig/issues/22600
      # Note that while this fix is already merged upstream and will be included in 0.14+,
      # we can't fetchpatch the upstream commit as it won't cleanly apply on older versions,
      # so we substitute the paths instead.
      + lib.optionalString (stdenvNoCC.hostPlatform.isDarwin && lib.versionOlder finalAttrs.version "0.14") ''
        substituteInPlace lib/std/zig/system/darwin.zig \
          --replace /usr/bin/xcrun xcrun \
          --replace /usr/bin/xcode-select xcode-select
      '';

    installPhase = ''
      install -Dt "$out/bin" zig
      cp -r lib doc "$out"
    '';
  });
in
  zig
