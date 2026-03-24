{
  description = "MoviePilot-flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);
      module = import ./module.nix;
    in
    {
      nixosModules.default = module;
      nixosModules.moviepilot = module;

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          eval = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot.enable = true;
                system.stateVersion = "25.05";
              })
            ];
          };
        in
        {
          module-eval = pkgs.runCommand "moviepilot-module-eval" { } ''
            echo ${lib.escapeShellArg eval.config.systemd.services.moviepilot-backend.description} >/dev/null
            touch "$out"
          '';
        });
    };
}
