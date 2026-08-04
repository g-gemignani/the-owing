{
  description = "Godot game development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.godot          # Godot 4 editor + runtime (GDScript build)
            # `keytool`, for the Android signing key (D157). In the shell rather than left to
            # `nix shell` per command because two things here need it: making the release key
            # and the local Android export BUILD.md describes, and the first run of
            # `tools/make_release_key.sh` failed on a missing JDK (D159).
            pkgs.jdk
          ];

          shellHook = ''
            echo "🎮 Godot $(godot --version 2>/dev/null | head -n1) ready — run 'godot' to open the editor."
          '';
        };
      });
}
