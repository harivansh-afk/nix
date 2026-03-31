{
  lib,
  fetchFromGitHub,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "sandbox-agent";
  version = "0.5.0-rc.1";

  src = fetchFromGitHub {
    owner = "rivet-dev";
    repo = "sandbox-agent";
    rev = "v0.5.0-rc.1";
    hash = "sha256-oeOpWjaQlQZZzwQGts4yJgL3STDCd3Hz2qbOJ4N2HBM=";
  };

  cargoLock.lockFile = ./Cargo.lock;

  prePatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  cargoBuildFlags = [
    "-p"
    "sandbox-agent"
  ];

  env.SANDBOX_AGENT_SKIP_INSPECTOR = "1";
  doCheck = false;

  meta = with lib; {
    description = "Universal API for coding agents in sandboxes";
    homepage = "https://sandboxagent.dev";
    license = licenses.asl20;
    mainProgram = "sandbox-agent";
    platforms = platforms.unix;
  };
}
