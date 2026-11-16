{
  description = "omaPOD, a podcast player for Omarchy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f s nixpkgs.legacyPackages.${s});
    in
    {
      packages = forAll (
        _: pkgs: rec {
          omapod = pkgs.callPackage ./nix/package.nix { };
          default = omapod;
        }
      );

      apps = forAll (
        s: _: {
          default = {
            type = "app";
            program = nixpkgs.lib.getExe self.packages.${s}.omapod;
          };
        }
      );

      overlays.default = final: _: { omapod = final.callPackage ./nix/package.nix { }; };

      checks = forAll (s: _: { package = self.packages.${s}.omapod; });
    };
}
