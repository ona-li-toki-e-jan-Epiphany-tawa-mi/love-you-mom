# This file is part of love-you-mom.
#
# Copyright (c) 2024 ona-li-toki-e-jan-Epiphany-tawa-mi
#
# love-you-mom is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# love-you-mom is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# love-you-mom. If not, see <https://www.gnu.org/licenses/>.

# Run 'nix develop path:.' to get a development environment.

{
  description = "love-you-mom development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs.lib) genAttrs systems;

      forAllSystems = f:
        genAttrs systems.flakeExposed
        (system: f { pkgs = import nixpkgs { inherit system; }; });
    in {
      devShells = forAllSystems ({ pkgs }: {
        default = with pkgs; mkShell { packages = [ zig_0_13 ]; };
      });
    };
}
