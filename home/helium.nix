{ ... }:
let
  extensions = {
    "ddkjiahejlhfcafbddmgiahcphecmpfh" = "uBlock Origin Lite";
    "fcoeoabgfenejglbffodgkkbkcdhcgfn" = "Claude for Chrome";
    "nngceckbapebfimnlniiiahkandclblb" = "Bitwarden";
  };

  extJson = builtins.toJSON {
    external_update_url = "https://clients2.google.com/service/update2/crx";
  };

  extDir = "Library/Application Support/net.imput.helium/External Extensions";
in
{
  home.file = builtins.listToAttrs (
    builtins.map (id: {
      name = "${extDir}/${id}.json";
      value.text = extJson;
    }) (builtins.attrNames extensions)
  );
}
