{
  fetchPnpmDeps,
  inputs,
  lib,
  nodejs_24,
  pnpm_9,
  pnpmConfigHook,
  prismaEngines,
  stdenvNoCC,
}:
assert lib.assertMsg (
  prismaEngines.version == "7.9.1"
) "rakazo: Prisma engines must match the pinned Prisma 7.9.1 client";
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rakazo";
  version = "0.1.0-${inputs.rakazo-src.shortRev or "dirty"}";
  src = inputs.rakazo-src;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_9;
    fetcherVersion = 3;
    hash = "sha256-KSDlQvaXmnXh6iWEhQ7bNpDT7DFiTXKt6Rt2munnNyI=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm_9
    pnpmConfigHook
    prismaEngines
  ];

  postPatch = ''
    substituteInPlace apps/api/src/index.ts \
      --replace-fail \
        'serve({ fetch: app.fetch, port: env.port }' \
        'serve({ fetch: app.fetch, port: env.port, hostname: "127.0.0.1" }'
    substituteInPlace packages/adapters/src/deployment-model.ts \
      --replace-fail \
        '    anthropic: env.ANTHROPIC_API_KEY,' \
        '    anthropic: env.ANTHROPIC_API_KEY,
    local: env.RAKAZO_LOCAL_MODELS?.trim() ? "local" : undefined,'
  '';

  buildPhase = ''
    runHook preBuild
    pnpm --filter @rakazo/db generate
    RAKAZO_ALLOW_DEV_SECRETS=1 pnpm --filter @rakazo/web build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib
    cp -R . $out/lib/rakazo
    runHook postInstall
  '';
})
