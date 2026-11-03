# Reasonix — DeepSeek-native AI coding agent CLI
# https://github.com/esengine/DeepSeek-Reasonix
#
# Distributed as a single static Go binary via GitHub release archives
# (also what upstream's npm/Homebrew installs ship). We fetch the prebuilt
# archives per platform; hashes verified against the release SHA256SUMS.
{
  lib,
  stdenv,
  fetchurl,
}: let
  version = "2.57.0";

  bins = {
    x86_64-linux = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-linux-amd64.tar.gz";
      hash = "sha256-wie7wIxlryfbzEmq6E4RWpEhI6Pit5AqZmis2nX7lI8=";
    };
    aarch64-linux = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-linux-arm64.tar.gz";
      hash = "sha256-0fWBhpN9TPg5EK0AB7C5IR2CAaHB5A79hbLOZqFrtKM=";
    };
    x86_64-darwin = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-darwin-amd64.tar.gz";
      hash = "sha256-GU975rGe+6HKn3GEKvIJoqrFgijncYtOMnUIuu8tsDg=";
    };
    aarch64-darwin = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-darwin-arm64.tar.gz";
      hash = "sha256-0/x6Z6zn8cfuICUEASoJIycxswKJE50IqGaxYQ0n62o=";
    };
  };

  system = stdenv.hostPlatform.system;
  bin = bins.${system} or (throw "reasonix: no prebuilt binary for ${system}");
in
  stdenv.mkDerivation {
    pname = "reasonix";
    inherit version;

    src = fetchurl {
      url = bin.url;
      hash = bin.hash;
    };

    # Release archives are flat (binary + docs at top level), not wrapped in a dir
    sourceRoot = ".";

    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 reasonix "$out/bin/reasonix"
      runHook postInstall
    '';

    meta = {
      description = "DeepSeek-native AI coding agent for the terminal (deepseek-reasonix)";
      homepage = "https://github.com/esengine/DeepSeek-Reasonix";
      changelog = "https://github.com/esengine/DeepSeek-Reasonix/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = "reasonix";
      platforms = builtins.attrNames bins;
    };
  }
