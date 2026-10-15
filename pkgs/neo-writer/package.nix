{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  appimageTools,
}: let
  pname = "neo-writer";
  version = "1.5.5";
  releases = {
    aarch64-darwin = {
      file = "NEO-${version}-arm64-mac.zip";
      hash = "sha256-ZJjaGxL8LWPwpHCwl99ImzuAXhxH2wICbmYHFt5fjdg=";
    };
    x86_64-darwin = {
      file = "NEO-${version}-mac.zip";
      hash = "sha256-ZMyp/PN7o+wCLWMVfeSe+LBGh4fxMLdChJwxtWmF1mc=";
    };
    aarch64-linux = {
      file = "NEO-${version}-arm64.AppImage";
      hash = "sha256-lES93xOFya6G+JBHczmTNC8IajPnXaFkMRmOzXCQVNQ=";
    };
    x86_64-linux = {
      file = "NEO-${version}.AppImage";
      hash = "sha256-EN1cZVmEAlEooTNkZtx0xBWwvz463NxBomxZB4cXVas=";
    };
  };
  release = releases.${stdenv.hostPlatform.system} or (throw "neo-writer: unsupported platform ${stdenv.hostPlatform.system}");
  src = fetchurl {
    url = "https://github.com/nightconcept/neo/releases/download/v${version}/${release.file}";
    inherit (release) hash;
  };
  meta = {
    description = "Distraction-free word processor for authors";
    homepage = "https://github.com/nightconcept/neo";
    changelog = "https://github.com/nightconcept/neo/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = builtins.attrNames releases;
  };
  appimageContents = appimageTools.extract {inherit pname version src;};
in
  if stdenv.hostPlatform.isDarwin
  then
    stdenvNoCC.mkDerivation {
      inherit pname version src meta;
      nativeBuildInputs = [unzip];
      sourceRoot = ".";
      dontConfigure = true;
      dontBuild = true;
      dontFixup = true;
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/Applications"
        cp -R NEO.app "$out/Applications/"
        runHook postInstall
      '';
    }
  else
    appimageTools.wrapType2 {
      inherit pname version src;
      meta = meta // {mainProgram = pname;};
      extraInstallCommands = ''
        install -Dm644 ${appimageContents}/neo.desktop "$out/share/applications/neo-writer.desktop"
        substituteInPlace "$out/share/applications/neo-writer.desktop" \
          --replace-fail 'Exec=AppRun' 'Exec=neo-writer'
        cp -r ${appimageContents}/usr/share/icons "$out/share/"
      '';
    }
