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
          ];

          shellHook = ''
            echo "🎮 Godot $(godot --version 2>/dev/null | head -n1) ready — run 'godot' to open the editor."
          '';
        };
      });
}
