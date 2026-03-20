if [[ $# -ne 1 ]]; then
  echo "usage: ni <package>"
  exit 1
fi

exec nix profile add "nixpkgs#$1"
