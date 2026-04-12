{
  lib,
  makeWrapper,
  stdenvNoCC,
  fetchurl,
}: let
  version = "0.66.1";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-darwin-arm64.tar.gz";
      hash = "sha256-/o8bGEZXl8nA9re7CXzyK7rV44ih3sNrVXtJc1L9Tlo=";
    };
    x86_64-darwin = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-darwin-x64.tar.gz";
      hash = "sha256-kyt99Gw6S+RzBZeWqZ0xRYuszRe8mlahsuPKd93rjZA=";
    };
    aarch64-linux = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-linux-arm64.tar.gz";
      hash = "sha256-ZN/tkyZdaeEOZ8eFKh89ZYq5SiKM7/qWAyEdqnHRo4U=";
    };
    x86_64-linux = {
      url = "https://github.com/badlogic/pi-mono/releases/download/v${version}/pi-linux-x64.tar.gz";
      hash = "sha256-/tcbqk/z+X/AkM4znue8mQ/GL47j6k8ysjTH8WfiDDA=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
    or (throw "pi is not packaged for ${stdenvNoCC.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation {
    pname = "pi";
    inherit version;

    src = fetchurl source;

    sourceRoot = "pi";

    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/libexec/pi
      cp -R ./* $out/libexec/pi/
      chmod +x $out/libexec/pi/pi
      makeWrapper $out/libexec/pi/pi $out/bin/pi

      runHook postInstall
    '';

    meta = {
      description = "Minimal terminal coding harness";
      homepage = "https://github.com/badlogic/pi-mono";
      license = lib.licenses.mit;
      platforms = builtins.attrNames sources;
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      mainProgram = "pi";
    };
  }
