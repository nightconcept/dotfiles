{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  appimageTools,
}: let
  pname = "neo-writer";
  version = "1.3.0";
  releases = {
    aarch64-darwin = {
      file = "NEO-${version}-arm64-mac.zip";
      hash = "sha256-F6t0P/ywFs/ar6C0J6uG3lyyt37GvdauycoGT8stUqw=";
    };
    x86_64-darwin = {
      file = "NEO-${version}-mac.zip";
      hash = "sha256-y6USld8Q6BHYlRP1WkKqBdPpXvSi5+Z7aGlxT+OBReY=";
    };
    aarch64-linux = {
      file = "NEO-${version}-arm64.AppImage";
      hash = "sha256-WiHZ/TAmbPuzN3ejbZdKV0qICdhquN4F9z2btfBQSr0=";
    };
    x86_64-linux = {
      file = "NEO-${version}.AppImage";
      hash = "sha256-3eFIJxqH3F/K5pOtPmxgR6h07jfA4SJLsYaydzCymSU=";
    };
  };
  release = releases.${stdenv.hostPlatform.system} or (throw "neo-writer: unsupported platform ${stdenv.hostPlatform.system}");
  src = fetchurl {
    url = "https://github.com/hughhowey/neo/releases/download/v${version}/${release.file}";
    inherit (release) hash;
  };
  meta = {
    description = "Distraction-free word processor for authors";
    homepage = "https://github.com/hughhowey/neo";
    changelog = "https://github.com/hughhowey/neo/releases/tag/v${version}";
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
