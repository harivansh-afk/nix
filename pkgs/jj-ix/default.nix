# jj-ix: jj with the ix store backend and `jj ix` commands, the client for
# the forge at forge.ix.dev. Installed beside stock `jj`. Built from the
# ix-src input with the nightly its rust-toolchain.toml names.
{
  lib,
  makeRustPlatform,
  rust-bin,
  ix-src,
  pkg-config,
}:
let
  toolchain = rust-bin.nightly."2026-05-27".minimal;
  rustPlatform = makeRustPlatform {
    cargo = toolchain;
    rustc = toolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "jj-ix";
  version = "0.1.0-unstable-2026-08-12";

  src = ix-src;

  # The cargo workspace root is the satellite, not the repo root.
  cargoRoot = "crates/jj/client";
  buildAndTestSubdir = "crates/jj/client/cli";

  cargoLock = {
    lockFile = "${ix-src}/crates/jj/client/Cargo.lock";
    outputHashes = {
      "snafu-0.9.1" = "sha256-eSNVZr0TxDguSSu9c3L6S7rwqq45NemtmTvxHdiDRgM=";
    };
  };

  # The repo's rustc-wrapper guard script needs /usr/bin/env and
  # IX_CARGO_ENVIRONMENT=nix, neither of which the sandbox has by default.
  postPatch = ''
    patchShebangs .cargo/rustc-wrapper
  '';
  env.IX_CARGO_ENVIRONMENT = "nix";

  nativeBuildInputs = [ pkg-config ];

  # Dev-deps pull in jj-server from the root workspace; upstream CI tests the client.
  doCheck = false;

  meta = {
    description = "jj with the ix store backend - client for the ix jj-native forge";
    homepage = "https://forge.ix.dev:8448/";
    license = lib.licenses.unfree; # LicenseRef-Proprietary in-repo
    mainProgram = "jj-ix";
    platforms = lib.platforms.unix;
  };
}
