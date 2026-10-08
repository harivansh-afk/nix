{
  requireFile,
  runCommand,
  python3,
  nonicons,
}:
let
  face =
    style: sha256:
    requireFile {
      name = "BerkeleyMono-${style}.otf";
      inherit sha256;
      message = ''
        Berkeley Mono is licensed and installed by hand. Add it to the store once:
          nix-store --add-fixed sha256 ~/Library/Fonts/BerkeleyMono-${style}.otf
      '';
    };
  faces = {
    Regular = face "Regular" "ec71c9f8a3d184368c43c8d469df7a8718f482a23b9b12ca991350141017bfc6";
    Bold = face "Bold" "39b7f146dea9877bb44a1007e2bd030a2484ff4bad9f9a410b808c8674540eaa";
  };
  python = python3.withPackages (ps: [ ps.fonttools ]);
in
runCommand "berkeley-mono-nonicons" { } ''
  mkdir -p $out/share/fonts/opentype
  ${python}/bin/python3 -I ${./merge.py} ${faces.Regular} ${nonicons}/share/fonts/truetype/nonicons.ttf \
    $out/share/fonts/opentype/BerkeleyMonoNonicons-Regular.otf "Berkeley Mono Nonicons" BerkeleyMonoNonicons-Regular
  ${python}/bin/python3 -I ${./merge.py} ${faces.Bold} ${nonicons}/share/fonts/truetype/nonicons.ttf \
    $out/share/fonts/opentype/BerkeleyMonoNonicons-Bold.otf "Berkeley Mono Nonicons" BerkeleyMonoNonicons-Bold
''
