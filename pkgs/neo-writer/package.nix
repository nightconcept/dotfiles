{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  appimageTools,
}: let
  pname = "neo-writer";
  version = "1.5.0";
  releases = {
    aarch64-darwin = {
      file = "NEO-${version}-arm64-mac.zip";
      hash = "sha256-ZnulLgUaMOpyLtPB9qvymecysVMe04fHQrIkvZ0duxk=";
    };
    x86_64-darwin = {
      file = "NEO-${version}-mac.zip";
      hash = "sha256-LVN8Roxf9VKfEyVRoJ/IcqG+c4pVcSIZDGlY/CUqNm4=";
    };
    aarch64-linux = {
      file = "NEO-${version}-arm64.AppImage";
      hash = "sha256-I5Txf9seYK+MI6P9fJdiaKJSN9A6+V7oZjvpwshX+84=";
    };
    x86_64-linux = {
      file = "NEO-${version}.AppImage";
      hash = "sha256-UYK/GDJ6p58l/8v6AM0MFvR33Ha9um9l/qPMBhTCWGo=";
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
