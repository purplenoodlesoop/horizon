{
  description = "Horizon — personal multi-agent assistant with vault-resident capabilities.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    core-flake = {
      url = "github:purplenoodlesoop/core-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { core-flake, ... }:
    with core-flake;
    lib.evalFlake {
      perSystem =
        { pkgs, ... }:
        let
          horizon = pkgs.callPackage ./nix/horizon.nix { };
        in
        {
          flake.packages.default = horizon;
        };
    };
}
