{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  upstream = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.minimal.hermesDesktop;
  stamp = pkgs.writeText "hermes-desktop-install-stamp.json" (
    builtins.toJSON {
      schemaVersion = 1;
      commit = inputs.hermes-agent.rev;
      branch = "nix";
      dirty = false;
      source = "nix";
    }
  );
  desktop = upstream.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      cp --remove-destination ${stamp} $out/share/hermes-desktop/install-stamp.json
    '';
  });
  plist = (pkgs.formats.plist { }).generate "hermes-desktop-Info.plist" {
    CFBundleExecutable = "hermes-desktop";
    CFBundleIconFile = "hermes";
    CFBundleIdentifier = "sh.harivan.hermes-desktop";
    CFBundleName = "Hermes";
    CFBundlePackageType = "APPL";
    CFBundleShortVersionString = desktop.version;
    CFBundleVersion = desktop.version;
    LSMinimumSystemVersion = "12.0";
  };
  bundle =
    pkgs.runCommand "hermes-desktop-app"
      {
        nativeBuildInputs = [
          pkgs.makeWrapper
          pkgs.libicns
        ];
      }
      ''
        contents="$out/Hermes.app/Contents"
        mkdir -p "$contents/MacOS" "$contents/Resources"
        cp ${plist} "$contents/Info.plist"
        makeWrapper ${lib.getExe desktop} "$contents/MacOS/hermes-desktop"
        png2icns "$contents/Resources/hermes.icns" \
          ${desktop}/share/icons/hicolor/1024x1024/apps/hermes.png
      '';
in
{
  environment.systemPackages = [ desktop ];

  system.activationScripts.postActivation.text = lib.mkAfter ''
    rm -rf /Applications/Hermes.app
    /usr/bin/ditto ${bundle}/Hermes.app /Applications/Hermes.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Hermes.app
  '';
}
