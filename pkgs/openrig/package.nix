# OpenRig — persistent teams of AI coding agents (Claude Code, Codex, Pi)
# https://github.com/mvschwarz/openrig
#
# Built from the published @openrig/cli npm tarball, which already ships the
# compiled CLI, daemon, UI and TUI. The tarball has no lockfile, so
# package-lock.json here is generated with
# `npm install --package-lock-only --ignore-scripts` in the unpacked tarball;
# regenerate it (and npmDepsHash) on every version bump.
{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs_22,
  python3,
  tmux,
}:
buildNpmPackage rec {
  pname = "openrig";
  version = "0.7.8";

  src = fetchurl {
    url = "https://registry.npmjs.org/@openrig/cli/-/cli-${version}.tgz";
    hash = "sha256-8XWlsY8tkVgfjzo3y0qoBwyimQ2PVXtjrBWzxqmUBEU=";
  };
  sourceRoot = "package";

  nodejs = nodejs_22;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-OO1Y76kxJnRyFYxobSBm3Fe7Qs2ndkBQC7fID+wi/f8=";

  # Already compiled upstream; postinstall is a runtime ABI check only.
  dontNpmBuild = true;
  npmFlags = ["--ignore-scripts"];
  nativeBuildInputs = [makeWrapper python3];

  # better-sqlite3 needs its native addon built since scripts are skipped.
  preInstall = ''
    npm rebuild better-sqlite3 --build-from-source
  '';

  postInstall = ''
    wrapProgram $out/bin/rig --prefix PATH : ${lib.makeBinPath [tmux]}
  '';

  meta = {
    description = "Build and run persistent networks of Claude Code, Codex and Pi agents";
    homepage = "https://github.com/mvschwarz/openrig";
    changelog = "https://github.com/mvschwarz/openrig/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "rig";
  };
}
