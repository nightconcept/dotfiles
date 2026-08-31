# Mise — Dev tools, env vars, task runner
# https://github.com/jdx/mise
#
# Distributed as standalone binaries via GitHub release archives.
# We fetch pre-built archives per platform to avoid compiling Rust from source on every update.
{
  lib,
  stdenv,
  fetchurl,
}: let
  version = "2026.8.14";

  bins = {
    x86_64-linux = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-linux-x64-musl.tar.gz";
      hash = "sha256-ODLznDJeND+B/j2SskR8XRpe6hvIUJK7e2wlgGIiZH4=";
    };
    aarch64-linux = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-linux-arm64-musl.tar.gz";
      hash = "sha256-Bhhs+/6UcEmyHVhXX7DqgAzCbtE3XyD0tnjLOp1nlDc=";
    };
    x86_64-darwin = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-macos-x64.tar.gz";
      hash = "sha256-YIXQt8e/jhdjl8SOPx4gJb1B1p3VDwXAjLeuift/d7E=";
    };
    aarch64-darwin = {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-macos-arm64.tar.gz";
      hash = "sha256-47pSa2KcQfp7CRj3jnRspxp6Swx42/rKn7JWdqMYdi4=";
    };
  };

  system = stdenv.hostPlatform.system;
  bin = bins.${system} or (throw "mise: no prebuilt binary for ${system}");
in
  stdenv.mkDerivation {
    pname = "mise";
    inherit version;

    src = fetchurl {
      url = bin.url;
      hash = bin.hash;
    };

    sourceRoot = ".";

    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r mise/* $out/
      runHook postInstall
    '';

    meta = {
      description = "The front-end to your dev env (prebuilt binary release)";
      homepage = "https://mise.jdx.dev";
      changelog = "https://github.com/jdx/mise/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = "mise";
      platforms = builtins.attrNames bins;
    };
  }
