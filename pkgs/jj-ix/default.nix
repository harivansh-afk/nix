# jj-ix: the patched jj binary carrying the ix store backend and the
# `jj ix ...` command group (clone/submit/forge/view/mount) - the client for
# the jj-native forge at https://forge.ix.dev:8447/rpc (ix ADR 0001/0002).
#
# This is a FULL jj (all stock commands are present), but forge-backed
# workspaces can only be opened by this binary: the ix store backend does not
# exist in stock `jujutsu`. Installed as `jj-ix` so the stock `jj` stays the
# default for ordinary git-backed repos.
#
# Source and toolchain both come from the ix repo's own pins:
#   - src = the archived GitHub mirror at its final commit (see the ix-src
#     flake input; the forge is not nix-fetchable today).
#   - rustc/cargo = nightly-2026-05-27 (rust-toolchain.toml at the ix repo
#     root; the satellite workspace needs nightly cargo for its
#     `cargo-features = ["profile-rustflags", "trim-paths"]`).
#
# The crate lives in a standalone cargo workspace at crates/jj/client (its
# path-deps reach the vendored jj fork at index/views/jj and a few ix root
# crates, which is why src must be the whole ix tree). Tests are skipped:
# the cli's dev-dependencies path-dep jj-server from the ix ROOT workspace,
# and building that drags in a far larger dependency closure than the
# binary needs.
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

  # The repo's .cargo/config.toml routes every rustc call through
  # .cargo/rustc-wrapper, a dev-shell guard script. Two problems in nix
  # sandboxes: its `#!/usr/bin/env bash` shebang has no /usr/bin/env on
  # Linux (exec fails with ENOENT), and on Darwin the guard aborts unless
  # IX_CARGO_ENVIRONMENT=nix is set.
  postPatch = ''
    patchShebangs .cargo/rustc-wrapper
  '';
  env.IX_CARGO_ENVIRONMENT = "nix";

  nativeBuildInputs = [ pkg-config ];

  # Dev-deps pull jj-server from the ix root workspace; the binary is what
  # we ship. Correctness of the client is exercised upstream in the forge's
  # own CI gate.
  doCheck = false;

  meta = {
    description = "jj with the ix store backend - client for the ix jj-native forge";
    homepage = "https://forge.ix.dev:8448/";
    license = lib.licenses.unfree; # LicenseRef-Proprietary in-repo
    mainProgram = "jj-ix";
    platforms = lib.platforms.unix;
  };
}
