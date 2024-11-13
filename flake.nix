# Run 'nix develop path:.' to get a development environment.

{
  description = "love-you-mom development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let inherit (nixpkgs.lib) genAttrs systems;

        forAllSystems = f: genAttrs systems.flakeExposed (system: f {
          pkgs = import nixpkgs { inherit system; };
        });
    in {
      devShells = forAllSystems ({ pkgs }: {
        default = with pkgs; mkShell {
          nativeBuildInputs = [
            zig_0_13
          ];
        };
      });
    };
}
