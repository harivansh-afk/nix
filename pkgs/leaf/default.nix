{
  lib,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
  pkg-config,
  oniguruma,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "leaf";
  version = "1.26.2";

  src = fetchFromGitHub {
    owner = "RivoLink";
    repo = "leaf";
    tag = finalAttrs.version;
    hash = "sha256-i56BfHHkWl6gfhYXhrwEymlPTc+V4msnxlV7LSUy8X0=";
  };

  cargoHash = "sha256-/IGQ0UTvQGU4KQKl5mocGeGEDx4AdMQQTv4B3bkpIJ0=";

  nativeBuildInputs = [
    installShellFiles
    pkg-config
  ];

  buildInputs = [ oniguruma ];

  env.RUSTONIG_SYSTEM_LIBONIG = true;

  postInstall = ''
    installShellCompletion --cmd leaf \
      --bash completions/leaf.bash \
      --fish completions/leaf.fish \
      --zsh completions/leaf.zsh
  '';

  meta = {
    description = "Terminal Markdown previewer with a GUI-like experience";
    homepage = "https://leaf.rivolink.mg";
    license = lib.licenses.mit;
    mainProgram = "leaf";
    platforms = lib.platforms.unix;
  };
})
