{ pkgs, hermes }:
pkgs.runCommand "hermes-conversation-0.1.0"
  {
    nativeBuildInputs = [ hermes.hermesVenv ];
  }
  ''
    export HOME=$TMPDIR/home HERMES_HOME=$TMPDIR/home/.hermes
    mkdir -p "$HERMES_HOME"
    export PYTHONPATH=${./.}
    python3 -m unittest discover -s ${./tests} -v
    mkdir -p $out
    cp ${./hermes_conversation}/*.py ${./hermes_conversation}/*.yaml ${./hermes_conversation}/*.md $out/
  ''
