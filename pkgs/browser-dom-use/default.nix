{
  lib,
  rustPlatform,
  pkg-config,
}:
let
  # Daily driver built from the working checkout on Spark. Switch to fetchgit once the
  # repository is public or a deploy key is wired into the build sandbox.
  src = builtins.path {
    path = /home/rathi/Documents/Git/browser-dom-use;
    name = "browser-dom-use-src";
    filter =
      path: _type:
      !(lib.hasInfix "/target" path || lib.hasInfix "/.worktrees" path || lib.hasInfix "/.git/" path);
  };
in
rustPlatform.buildRustPackage {
  pname = "browser-dom-use";
  version = "0.1.0";
  inherit src;
  cargoLock.lockFile = src + "/Cargo.lock";
  nativeBuildInputs = [ pkg-config ];
  doCheck = false;
  postInstall = ''
    mkdir -p $out/share/bdu
    cp -r $src/skills $out/share/bdu/skills
  '';
  meta = {
    description = "A browser for agents that pays the model once per task";
    homepage = "https://git.harivan.sh/harivansh-afk/browser-dom-use";
    license = lib.licenses.mit;
    mainProgram = "bdu";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
