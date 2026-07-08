# inventory

Typed host inventory. One record per host, validated against a schema with
`lib.evalModules`, consumed by `flake/args.nix` (`import ../inventory`).

## Layout

- `schema.nix` - the host record submodule (the contract every node must satisfy).
- `nodes/<host>.nix` - one record per host (`macbook.nix`, `spark.nix`).
- `default.nix` - reads every `nodes/*.nix`, evaluates them against the schema,
  enforces invariants, and returns the `nodes` attrset.

## Record fields (`schema.nix`)

| Field           | Type                          | Notes                                  |
|-----------------|-------------------------------|----------------------------------------|
| `name`          | str                           | Defaults to the file name; must match it |
| `kind`          | enum `darwin` \| `nixos`      | Required                               |
| `system`        | enum of the 4 nix systems     | Required                               |
| `hostname`      | str                           | Defaults to `name`                     |
| `username`      | str                           | Required; the host's primary user      |
| `roles`         | list of str                   | Defaults to `[]`                       |
| `homeDirectory` | str                           | Defaults by platform from `username`   |
| `isDarwin` / `isLinux` / `isNixOS` | bool (read-only) | Derived from `kind`                  |

## Invariants (`default.nix`)

Evaluation fails fast if any node violates:

- `name` matches its file name.
- `kind = darwin` implies a `-darwin` system.
- `kind = nixos` implies a `-linux` system.

## Adding a host

Create `nodes/<host>.nix` with at least `kind`, `system`, and `username`. It is
picked up automatically.
