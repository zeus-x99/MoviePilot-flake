{
  description = "Example NixOS host using MoviePilot-flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    moviepilotFlake.url = "github:zeus-x99/MoviePilot-flake";
  };

  outputs = { nixpkgs, moviepilotFlake, ... }: {
    nixosConfigurations.nas = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        moviepilotFlake.nixosModules.default
        ({ pkgs, ... }: {
          services.moviepilot = {
            enable = true;
            openFirewall = true;
            stateDir = "/var/lib/moviepilot";
            environmentFile = "/run/secrets/moviepilot.env";

            settings = {
              SUPERUSER = "admin";
              DB_TYPE = "sqlite";
              AUTH_SITE = "iyuu";
            };

            extraPackages = with pkgs; [
              ffmpeg
              mediainfo
              rclone
            ];
          };

          system.stateVersion = "25.05";
        })
      ];
    };
  };
}
