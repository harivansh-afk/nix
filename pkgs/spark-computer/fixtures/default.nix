{ pkgs }:
let
  python = pkgs.python3.withPackages (ps: [ ps.pygobject3 ]);
in
pkgs.stdenvNoCC.mkDerivation {
  name = "spark-computer-native-fixture";
  dontUnpack = true;
  nativeBuildInputs = [
    pkgs.wrapGAppsHook3
    pkgs.gobject-introspection
  ];
  buildInputs = [ pkgs.gtk3 ];
  installPhase = ''
    mkdir -p $out/bin
    cat > $out/bin/spark-computer-native-fixture <<'EOF'
    #!${pkgs.runtimeShell}
    export NO_AT_BRIDGE=0 GTK_A11Y=always
    exec ${python}/bin/python ${./native.py} "$@"
    EOF
    chmod +x $out/bin/spark-computer-native-fixture
  '';
}
