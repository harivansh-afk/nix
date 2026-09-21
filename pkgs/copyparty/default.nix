{ pkgs }:
let
  version = "1.20.24";
  src = pkgs.fetchurl {
    url = "https://github.com/9001/copyparty/releases/download/v${version}/copyparty-${version}.tar.gz";
    hash = "sha256-RQ3KfVcB5nI12RbgNfzCFDMozh0Ka1t+PF0sI727c+M=";
  };
  uploader = pkgs.runCommand "copyparty-uploader-${version}" { } ''
    mkdir -p $out
    tar -xzf ${src} --strip-components=2 -C $out copyparty-${version}/bin/u2c.py
  '';
in
(pkgs.copyparty.override {
  withCertgen = false;
  withThumbnails = false;
  withMediaProcessing = false;
  withZeroMQ = false;
  withFTP = false;
}).overrideAttrs
  (old: {
    inherit version src;
    passthru = (old.passthru or { }) // {
      inherit uploader;
    };
  })
