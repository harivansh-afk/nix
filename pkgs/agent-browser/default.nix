{
  lib,
  rustPlatform,
  which,
  src,
}:
let
  cargo = builtins.fromTOML (builtins.readFile "${src}/cli/Cargo.toml");
in
rustPlatform.buildRustPackage {
  pname = "agent-browser";
  version = "${cargo.package.version}-${src.shortRev or "dirty"}";
  inherit src;

  sourceRoot = "source/cli";

  cargoLock.lockFile = "${src}/cli/Cargo.lock";

  postUnpack = ''
    chmod -R u+w source
  '';

  postPatch = ''
    substituteInPlace src/doctor/helpers.rs src/install.rs --replace-fail \
      '"which"' '"${lib.getExe which}"'
  '';

  doCheck = false;

  postInstall = ''
    cp -r ../skills $out/skills
    cp -r ../skill-data $out/skill-data
  '';

  meta = {
    description = "Browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    mainProgram = "agent-browser";
  };
}
