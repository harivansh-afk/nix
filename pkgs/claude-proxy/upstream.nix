{
  lib,
  buildGo126Module,
  fetchFromGitHub,
}:
buildGo126Module (finalAttrs: {
  pname = "cli-proxy-api";
  version = "8.0.22";

  src = fetchFromGitHub {
    owner = "router-for-me";
    repo = "CLIProxyAPI";
    tag = "v${finalAttrs.version}";
    hash = "sha256-xnD8MxjILDyOqblOSSC8syhvZ9hvW0cL8xoktemiDn8=";
  };

  vendorHash = "sha256-r3yWkdMcM40G9jV7MxW/qNv3E9WrHavFilW24quEf+8=";
  env.CGO_ENABLED = "0";
  subPackages = [ "cmd/server" ];
  postPatch = ''
    substituteInPlace internal/auth/claude/oauth_server.go \
      --replace-fail 'fmt.Sprintf(":%d", s.port)' 'fmt.Sprintf("127.0.0.1:%d", s.port)'
  '';
  ldflags = [
    "-s"
    "-w"
    "-X main.Version=${finalAttrs.version}"
    "-X main.Commit=v${finalAttrs.version}"
  ];

  doCheck = false;

  postInstall = ''
    mv "$out/bin/server" "$out/bin/cli-proxy-api"
  '';

  meta = {
    description = "Local API gateway for CLI model providers";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cli-proxy-api";
    platforms = lib.platforms.unix;
  };
})
