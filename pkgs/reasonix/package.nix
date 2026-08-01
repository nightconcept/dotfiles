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
}:
let
  version = "1.18.0";

  bins = {
    x86_64-linux = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-linux-amd64.tar.gz";
      hash = "sha256-cpSTnaLtXFj3zCA8lCR5ka29hZMQIDafqVmmuK48J9M=";
    };
    aarch64-linux = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-linux-arm64.tar.gz";
      hash = "sha256-xlnnxhrQpOySgqvH2Xk8FwW2SweoZADAUBJ2GW+AAMg=";
    };
    x86_64-darwin = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-darwin-amd64.tar.gz";
      hash = "sha256-vwxJQ08hp2Zk1jKb17IPw+FrBUVhp9Zwyn3LwLtLtW8=";
    };
    aarch64-darwin = {
      url = "https://github.com/esengine/DeepSeek-Reasonix/releases/download/v${version}/reasonix-darwin-arm64.tar.gz";
      hash = "sha256-Uu/UCIAFbWClnXiMZxTF+ZNiSX7ydRKgQGM92b41/ew=";
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
