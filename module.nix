{ config, lib, pkgs, ... }:

let
  inherit (lib)
    escapeShellArg
    literalExpression
    mapAttrs
    mkEnableOption
    mkIf
    mkOption
    optional
    optionals
    optionalAttrs
    types;

  cfg = config.services.moviepilot;

  sourceType = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        example = "https://github.com/jxxghp/MoviePilot.git";
      };

      ref = mkOption {
        type = types.str;
        example = "v2";
      };
    };
  };

  serializeEnv = value:
    if builtins.isBool value then lib.boolToString value
    else if builtins.isInt value || builtins.isFloat value then toString value
    else toString value;

  managedEnv = {
    CONFIG_DIR = "${cfg.stateDir}/config";
    HOST = cfg.host;
    PORT = toString cfg.backend.port;
    NGINX_PORT = toString cfg.frontend.port;
    TZ = cfg.timeZone;
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PYTHONUNBUFFERED = "1";
  } // mapAttrs (_: value: serializeEnv value) cfg.settings;

  commonPath = with pkgs; [
    coreutils
    findutils
    gcc
    git
    gnugrep
    gnumake
    gnused
    jq
    nodejs_20
    pkg-config
    python312
    rsync
    which
    yarn
  ];

  prepareScript = ''
    set -euo pipefail

    state_dir=${escapeShellArg cfg.stateDir}
    src_dir="$state_dir/src"
    runtime_dir="$state_dir/runtime"
    cache_dir="$state_dir/.cache"
    home_dir="$state_dir/.home"
    venv_dir="$state_dir/venv"
    backend_src="$src_dir/backend"
    frontend_src="$src_dir/frontend"
    plugins_src="$src_dir/plugins"
    resources_src="$src_dir/resources"
    backend_runtime="$runtime_dir/backend"
    frontend_runtime="$runtime_dir/frontend"

    export HOME="$home_dir"
    export PIP_CACHE_DIR="$cache_dir/pip"
    export YARN_CACHE_FOLDER="$cache_dir/yarn"

    install -d -m 0750 "$state_dir" "$src_dir" "$runtime_dir" "$cache_dir" "$home_dir"
    install -d -m 0750 "$state_dir/config" "$state_dir/config/logs" "$state_dir/config/temp" "$state_dir/config/cookies"

    sync_repo() {
      local url="$1"
      local ref="$2"
      local dir="$3"

      if [ ! -d "$dir/.git" ]; then
        rm -rf "$dir"
        git clone --filter=blob:none --branch "$ref" --depth 1 "$url" "$dir"
      else
        git -C "$dir" remote set-url origin "$url"
        git -C "$dir" fetch --depth 1 origin "$ref"
        git -C "$dir" reset --hard FETCH_HEAD
        git -C "$dir" clean -fdx
      fi
    }

    sync_repo ${escapeShellArg cfg.sources.backend.url} ${escapeShellArg cfg.sources.backend.ref} "$backend_src"
    sync_repo ${escapeShellArg cfg.sources.frontend.url} ${escapeShellArg cfg.sources.frontend.ref} "$frontend_src"
    sync_repo ${escapeShellArg cfg.sources.plugins.url} ${escapeShellArg cfg.sources.plugins.ref} "$plugins_src"
    sync_repo ${escapeShellArg cfg.sources.resources.url} ${escapeShellArg cfg.sources.resources.ref} "$resources_src"

    backend_rev="$(git -C "$backend_src" rev-parse HEAD)"
    frontend_rev="$(git -C "$frontend_src" rev-parse HEAD)"
    plugins_rev="$(git -C "$plugins_src" rev-parse HEAD)"
    resources_rev="$(git -C "$resources_src" rev-parse HEAD)"

    backend_stamp="$(
      {
        printf '%s\n' "$backend_rev"
        sha256sum "$backend_src/requirements.txt" "$backend_src/requirements.in"
      } | sha256sum | cut -d' ' -f1
    )"

    if [ ! -x "$venv_dir/bin/python" ] || [ ! -f "$venv_dir/.backend-stamp" ] || [ "$(cat "$venv_dir/.backend-stamp")" != "$backend_stamp" ]; then
      rm -rf "$venv_dir"
      ${pkgs.python312}/bin/python3 -m venv "$venv_dir"
      "$venv_dir/bin/pip" install --upgrade "pip<25.0" setuptools wheel
      "$venv_dir/bin/pip" install -r "$backend_src/requirements.txt"
      printf '%s' "$backend_stamp" > "$venv_dir/.backend-stamp"
    fi

    install -d -m 0750 "$backend_runtime"
    rsync -a --delete \
      --exclude '.git/' \
      --exclude 'app/plugins/' \
      "$backend_src/" "$backend_runtime/"

    install -d -m 0750 "$backend_runtime/app/plugins" "$backend_runtime/app/helper"
    cp -f "$backend_src/app/plugins/__init__.py" "$backend_runtime/app/plugins/__init__.py"

    if [ -d "$plugins_src/plugins.v2" ]; then
      rsync -a "$plugins_src/plugins.v2/" "$backend_runtime/app/plugins/"
    fi

    if [ -d "$plugins_src/plugins" ]; then
      for plugin_dir in "$plugins_src"/plugins/*; do
        [ -d "$plugin_dir" ] || continue
        plugin_name="$(basename "$plugin_dir")"
        if [ ! -e "$backend_runtime/app/plugins/$plugin_name" ]; then
          rsync -a "$plugin_dir/" "$backend_runtime/app/plugins/$plugin_name/"
        fi
      done
    fi

    if [ -d "$resources_src/resources.v2" ]; then
      rsync -a "$resources_src/resources.v2/" "$backend_runtime/app/helper/"
    fi

    if [ -d "$resources_src/resources" ]; then
      for resource_file in "$resources_src"/resources/*; do
        [ -e "$resource_file" ] || continue
        resource_name="$(basename "$resource_file")"
        if [ ! -e "$backend_runtime/app/helper/$resource_name" ]; then
          cp -f "$resource_file" "$backend_runtime/app/helper/$resource_name"
        fi
      done
    fi

    install -d -m 0750 "$frontend_runtime"
    rsync -a --delete \
      --exclude '.git/' \
      --exclude 'dist/' \
      --exclude 'node_modules/' \
      "$frontend_src/" "$frontend_runtime/"

    install -d -m 0750 "$frontend_runtime/public/plugin_icon"
    if [ -d "$plugins_src/icons" ]; then
      rsync -a "$plugins_src/icons/" "$frontend_runtime/public/plugin_icon/"
    fi

    frontend_stamp="$(
      {
        printf '%s\n' "$frontend_rev" "$plugins_rev" "$resources_rev"
        sha256sum "$frontend_src/package.json" "$frontend_src/yarn.lock"
      } | sha256sum | cut -d' ' -f1
    )"

    if [ ! -d "$frontend_runtime/node_modules" ] || [ ! -f "$frontend_runtime/.frontend-stamp" ] || [ "$(cat "$frontend_runtime/.frontend-stamp")" != "$frontend_stamp" ]; then
      (
        cd "$frontend_runtime"
        yarn install --frozen-lockfile --network-timeout 600000
        yarn build
      )
      printf '%s' "$frontend_stamp" > "$frontend_runtime/.frontend-stamp"
    fi
  '';
in
{
  options.services.moviepilot = {
    enable = mkEnableOption "MoviePilot source deployment";

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

    sources = {
      backend = mkOption {
        type = sourceType;
        default = {
          url = "https://github.com/jxxghp/MoviePilot.git";
          ref = "v2";
        };
      };

      frontend = mkOption {
        type = sourceType;
        default = {
          url = "https://github.com/jxxghp/MoviePilot-Frontend.git";
          ref = "v2";
        };
      };

      plugins = mkOption {
        type = sourceType;
        default = {
          url = "https://github.com/jxxghp/MoviePilot-Plugins.git";
          ref = "main";
        };
      };

      resources = mkOption {
        type = sourceType;
        default = {
          url = "https://github.com/jxxghp/MoviePilot-Resources.git";
          ref = "main";
        };
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
      "d ${cfg.stateDir}/src 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/runtime 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/.cache 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.stateDir}/.home 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts =
      optionals cfg.openFirewall ([ cfg.backend.port ] ++ optional cfg.frontend.enable cfg.frontend.port);

    systemd.services.moviepilot-prepare = {
      description = "Prepare MoviePilot source tree";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = commonPath;
      environment = managedEnv;
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0027";
      } // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
      script = prepareScript;
    };

    systemd.services.moviepilot-backend = {
      description = "MoviePilot backend";
      wantedBy = [ "multi-user.target" ];
      requires = [ "moviepilot-prepare.service" ];
      after = [
        "moviepilot-prepare.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      path = commonPath;
      environment = managedEnv;
      serviceConfig = {
        WorkingDirectory = "${cfg.stateDir}/runtime/backend";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "10s";
      } // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
      script = ''
        exec ${escapeShellArg "${cfg.stateDir}/venv/bin/python"} -m app.main
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
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      path = commonPath;
      environment = managedEnv;
      serviceConfig = {
        WorkingDirectory = "${cfg.stateDir}/runtime/frontend/dist";
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
