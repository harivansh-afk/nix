# VoiceInk Word Replacements dictionary, version-controlled and placed on the
# macbook declaratively. dots/voiceink/dictionary.json is the source of truth
# (a VoiceInk settings-backup file containing wordReplacements + vocabulary).
#
# VoiceInk has no import CLI and stores the dictionary in a CloudKit-mirrored
# SwiftData store, so we can't safely write it directly. Instead we drop the
# JSON next to VoiceInk's data on every rebuild; importing it is a one-time
# manual step: VoiceInk -> Settings -> Import Settings -> pick the file ->
# select Dictionary. Re-import only needed after the JSON changes.
{
  lib,
  username,
  ...
}:
let
  home = "/Users/${username}";
  dir = "${home}/Library/Application Support/VoiceInk";
  dest = "${dir}/VoiceInk_Dictionary_Import.json";
  src = ../../dots/voiceink/dictionary.json;
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "placing VoiceInk dictionary import file..."
    sudo -u ${username} mkdir -p ${lib.escapeShellArg dir}
    sudo -u ${username} install -m0644 ${src} ${lib.escapeShellArg dest} \
      || echo "warning: VoiceInk dictionary placement failed" >&2
  '';
}
