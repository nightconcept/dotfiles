{
  lib,
  makeWrapper,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}: let
  version = "1.44.0";

  sources = {
    x86_64-linux = {
      url = "https://github.com/block/goose/releases/download/v${version}/goose-x86_64-unknown-linux-gnu.tar.gz";
      hash = "sha256-B/68i09zvf3D7OPTTQ4hsAXzpPQwCPlbhdZTjaj2usE=";
    };
    aarch64-linux = {
      url = "https://github.com/block/goose/releases/download/v${version}/goose-aarch64-unknown-linux-gnu.tar.gz";
      hash = "sha256-2mywBdQhsL3Lg/6Dhrpa6AYO8XrfZGQaaE1PxLnhwV8=";
    };
    x86_64-darwin = {
      url = "https://github.com/block/goose/releases/download/v${version}/goose-x86_64-apple-darwin.tar.gz";
      hash = "sha256-Ok+Ju8FESMpMuPKLe0Hn6JHBMKVG1u5qzYyy/3fLO00=";
    };
    aarch64-darwin = {
      url = "https://github.com/block/goose/releases/download/v${version}/goose-aarch64-apple-darwin.tar.gz";
      hash = "sha256-+hcpPUh3is5gvzzc+7L8vXRighaiLMRbAgvRykW0IXA=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
    or (throw "goose-cli is not packaged for ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "goose-cli";
    inherit version;

    src = fetchurl source;

    dontUnpack = true;

    nativeBuildInputs = [makeWrapper] ++ lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [stdenv.cc.cc.lib];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      tar -xzf $src -C $out/bin
      chmod +x $out/bin/goose

      runHook postInstall
    '';

    meta = {
      description = "Block's open-source AI agent (goose) CLI, with ACP support";
      homepage = "https://github.com/block/goose";
      license = lib.licenses.asl20;
      platforms = builtins.attrNames sources;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "goose";
    };
  }
