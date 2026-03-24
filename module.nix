{ self }:
{ config, lib, pkgs, ... }:

let
  inherit (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    optional
    optionals
    optionalAttrs
    types;

  cfg = config.services.moviepilot;
  runtimeDir = "${cfg.stateDir}/runtime";
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  defaultSettings = {
    AUTO_UPDATE_RESOURCE = false;
  };
  effectiveSettings = defaultSettings // cfg.settings;

  serializeEnv = value:
    if builtins.isBool value then lib.boolToString value
    else if builtins.isInt value || builtins.isFloat value then toString value
    else toString value;

  managedEnv = {
    CONFIG_DIR = "${cfg.stateDir}/config";
    HOME = cfg.stateDir;
    HOST = cfg.host;
    PORT = toString cfg.backend.port;
    NGINX_PORT = toString cfg.frontend.port;
    TZ = cfg.timeZone;
    PLAYWRIGHT_BROWSERS_PATH =
      if builtins.hasAttr "browsers-chromium" cfg.playwrightPackage then
        "${cfg.playwrightPackage."browsers-chromium"}"
      else
        "${cfg.playwrightPackage.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PYTHONNOUSERSITE = "1";
    PYTHONPATH = "${runtimeDir}/backend";
    PYTHONUNBUFFERED = "1";
    MOVIEPILOT_NIX_PURE = "1";
  } // lib.mapAttrs (_: value: serializeEnv value) effectiveSettings;
in
{
  options.services.moviepilot = {
    enable = mkEnableOption "MoviePilot";

    package = mkOption {
      type = types.package;
      default = packages.moviepilot-runtime;
    };

    pythonPackage = mkOption {
      type = types.package;
      default = packages.moviepilot-python;
    };

    playwrightPackage = mkOption {
      type = types.package;
      default = packages.moviepilot-playwright-driver;
    };

    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/moviepilot";
      example = "/srv/moviepilot";
    };

    user = mkOption {
      type = types.str;
      default = "moviepilot";
    };

    group = mkOption {
      type = types.str;
      default = "moviepilot";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
    };

    timeZone = mkOption {
      type = types.str;
      default = if config.time.timeZone != null then config.time.timeZone else "Asia/Shanghai";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = literalExpression "/run/secrets/moviepilot.env";
    };

    settings = mkOption {
      type = types.attrsOf (types.oneOf [
        types.bool
        types.float
        types.int
        types.str
      ]);
      default = { };
      example = literalExpression ''
        {
          SUPERUSER = "admin";
          DB_TYPE = "sqlite";
        }
      '';
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [
        ffmpeg
        mediainfo
        rclone
      ];
    };

    backend.port = mkOption {
      type = types.port;
      default = 3001;
    };

    frontend = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };

      port = mkOption {
        type = types.port;
        default = 3000;
      };
    };
  };

  config = mkIf cfg.enable {
    users.groups = mkIf (cfg.group == "moviepilot") {
      moviepilot = { };
    };

    users.users = mkIf (cfg.user == "moviepilot") {
      moviepilot = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = false;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/config 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/runtime 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/runtime/backend 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/runtime/frontend 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts =
      optionals cfg.openFirewall ([ cfg.backend.port ] ++ optional cfg.frontend.enable cfg.frontend.port);

    systemd.services.moviepilot-prepare = {
      description = "Prepare MoviePilot runtime tree";
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        coreutils
        findutils
        rsync
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        UMask = "0027";
      } // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
      script = ''
        set -euo pipefail

        pkg_dir=${cfg.package}/share/moviepilot
        runtime_dir=${runtimeDir}

        install -d -m 0750 "$runtime_dir/backend" "$runtime_dir/frontend"

        rsync -a --delete \
          --exclude 'app/plugins/' \
          --exclude 'app/helper/' \
          "$pkg_dir/backend/" "$runtime_dir/backend/"

        chmod -R u+w "$runtime_dir/backend"
        install -d -m 0750 "$runtime_dir/backend/app/plugins" "$runtime_dir/backend/app/helper"

        rsync -a "$pkg_dir/backend/app/plugins/" "$runtime_dir/backend/app/plugins/"
        rsync -a "$pkg_dir/backend/app/helper/" "$runtime_dir/backend/app/helper/"
        rsync -a --delete "$pkg_dir/frontend/" "$runtime_dir/frontend/"

        chown -R ${cfg.user}:${cfg.group} "$runtime_dir"
        chmod -R u+rwX,go-rwx "$runtime_dir"
      '';
    };

    systemd.services.moviepilot-backend = {
      description = "MoviePilot backend";
      wantedBy = [ "multi-user.target" ];
      requires = [ "moviepilot-prepare.service" ];
      after = [ "moviepilot-prepare.service" ];
      path = cfg.extraPackages;
      environment = managedEnv;
      serviceConfig = {
        WorkingDirectory = "${runtimeDir}/backend";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "10s";
      } // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
      script = ''
        exec ${cfg.pythonPackage}/bin/python -m app.main
      '';
    };

    systemd.services.moviepilot-frontend = mkIf cfg.frontend.enable {
      description = "MoviePilot frontend";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "moviepilot-prepare.service"
        "moviepilot-backend.service"
      ];
      after = [
        "moviepilot-prepare.service"
        "moviepilot-backend.service"
      ];
      environment = managedEnv;
      serviceConfig = {
        WorkingDirectory = "${runtimeDir}/frontend/dist";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "10s";
      } // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
      script = ''
        exec ${pkgs.nodejs_20}/bin/node service.js
      '';
    };
  };
}
