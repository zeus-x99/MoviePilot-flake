{
  description = "Example NixOS host using MoviePilotNix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    moviepilotNix.url = "github:zeus-x99/MoviePilotNix";
  };

  outputs = { nixpkgs, moviepilotNix, ... }: {
    nixosConfigurations.nas = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        moviepilotNix.nixosModules.default
        ({ pkgs, ... }: {
          services.moviepilot = {
            enable = true;
            openFirewall = true;
            stateDir = "/var/lib/moviepilot";
            environmentFile = "/run/secrets/moviepilot.env";

            settings = {
              SUPERUSER = "admin";
              DB_TYPE = "sqlite";
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
