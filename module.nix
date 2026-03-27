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
    optionalString
    types;

  cfg = config.services.moviepilot;
  resolvePlaywrightBrowsersPath = import ./nix/playwright-browsers-path.nix;
  pathIsEqualOrUnder = prefix: path: path == prefix || lib.hasPrefix "${prefix}/" path;
  runtimeDir = "${cfg.stateDir}/runtime";
  stateDirDisablesProtectHome = lib.any (
    prefix: pathIsEqualOrUnder prefix cfg.stateDir
  ) [
    "/home"
    "/root"
    "/run/user"
  ];
  stateDirInStore = pathIsEqualOrUnder "/nix/store" cfg.stateDir;
  prepareReadWritePaths = [
    "${cfg.stateDir}/config"
    runtimeDir
  ];
  backendReadWritePaths = [ "${cfg.stateDir}/config" ];
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  backendPackage = cfg.backendPackage;
  normalizeAllowedDevice = device:
    if builtins.isString device then
      {
        path = device;
        permissions = "rw";
      }
    else
      device;
  pluginsPackage = cfg.pluginsPackage;
  resourcesPackage = cfg.resourcesPackage;
  backendSourceDir = "${backendPackage}/share/moviepilot/backend";
  pluginsSourceDir = "${pluginsPackage}/share/moviepilot/plugins";
  pluginsManifestSource = "${pluginsPackage}/share/moviepilot/plugins-manifest";
  resourcesSourceDir = "${resourcesPackage}/share/moviepilot/resources";
  resourcesManifestSource = "${resourcesPackage}/share/moviepilot/resources-manifest";
  defaultSettings = {
    AUTO_UPDATE_RESOURCE = false;
  };
  effectiveSettings = defaultSettings // cfg.settings;
  backendAllowedDeviceSpecs = map normalizeAllowedDevice cfg.backend.allowedDevices;
  allowedDevicePermissionRank = {
    r = 0;
    rw = 1;
    rwm = 2;
  };
  backendAllowedDevicePermissionsByPath =
    builtins.foldl' (
      acc: device:
      acc
      // {
        "${device.path}" = (acc.${device.path} or [ ]) ++ [ device.permissions ];
      }
    ) { } backendAllowedDeviceSpecs;
  backendAllowedDeviceMergeState =
    builtins.foldl' (
      acc: device:
      let
        existing = acc.byPath.${device.path} or null;
        keepCurrent =
          existing == null
          || allowedDevicePermissionRank.${device.permissions} > allowedDevicePermissionRank.${existing.permissions};
      in
      {
        byPath =
          acc.byPath
          // {
            "${device.path}" =
              if keepCurrent then
                device
              else
                existing;
          };
        order =
          if existing == null then
            acc.order ++ [ device.path ]
          else
            acc.order;
      }
    ) {
      byPath = { };
      order = [ ];
    } backendAllowedDeviceSpecs;
  backendResolvedAllowedDeviceSpecs =
    map (path: backendAllowedDeviceMergeState.byPath.${path}) backendAllowedDeviceMergeState.order;
  backendWhitelistedDevices = map (device: device.path) backendResolvedAllowedDeviceSpecs;
  backendSupplementaryGroups = lib.unique cfg.backend.supplementaryGroups;
  backendUsesWhitelistedDevices = backendWhitelistedDevices != [ ];
  backendDeviceAllow = map (device: "${device.path} ${device.permissions}") backendResolvedAllowedDeviceSpecs;
  scalarValueType = types.oneOf [
    types.bool
    types.float
    types.int
    types.str
  ];
  backendDuplicateAllowedDevicePaths = builtins.filter (
    path: lib.length backendAllowedDevicePermissionsByPath.${path} > 1
  ) (builtins.attrNames backendAllowedDevicePermissionsByPath);
  backendConflictingAllowedDevicePaths = builtins.filter (
    path: lib.length (lib.unique backendAllowedDevicePermissionsByPath.${path}) > 1
  ) backendDuplicateAllowedDevicePaths;
  backendDuplicateOnlyAllowedDevicePaths = builtins.filter (
    path: !(lib.elem path backendConflictingAllowedDevicePaths)
  ) backendDuplicateAllowedDevicePaths;
  backendConflictingAllowedDeviceSummaries = map (
    path: "${path} -> ${backendAllowedDeviceMergeState.byPath.${path}.permissions}"
  ) backendConflictingAllowedDevicePaths;
  backendNeedsRenderGroup = builtins.any (
    path: path == "/dev/dri" || lib.hasPrefix "/dev/dri/" path
  ) backendWhitelistedDevices;
  backendNeedsVideoGroup = builtins.any (
    path: lib.hasPrefix "/dev/video" path
  ) backendWhitelistedDevices;
  environmentFileInStore =
    cfg.environmentFile != null && pathIsEqualOrUnder "/nix/store" cfg.environmentFile;
  reservedSettingNames = [
    "CONFIG_DIR"
    "HOME"
    "HOST"
    "PORT"
    "NGINX_PORT"
    "TZ"
    "PLAYWRIGHT_BROWSERS_PATH"
    "PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD"
    "PYTHONDONTWRITEBYTECODE"
    "PYTHONNOUSERSITE"
    "PYTHONPATH"
    "PYTHONUNBUFFERED"
    "MOVIEPILOT_NIX_PURE"
  ];
  conflictingSettingNames = lib.intersectLists reservedSettingNames (builtins.attrNames cfg.settings);
  publicPort = if cfg.frontend.enable then cfg.frontend.port else cfg.backend.port;
  defaultPlaywrightBrowsersPath = resolvePlaywrightBrowsersPath packages.moviepilot-playwright-driver;
  resolvedPlaywrightBrowsersPath = "${cfg.playwrightBrowsersPath}";
  serializeJsonForPython = value: builtins.toJSON (builtins.toJSON value);
  downloadersConfigured = cfg.downloaders != [ ];
  directoriesConfigured = cfg.directories != [ ];
  mediaServersConfigured = cfg.mediaServers != [ ];
  storagesConfigured = cfg.storages != [ ];
  serializedDownloaders = map (
    downloader:
    (builtins.removeAttrs downloader [ "pathMapping" ])
    // {
      path_mapping = map (mapping: [
        mapping.source
        mapping.target
      ]) downloader.pathMapping;
    }
  ) cfg.downloaders;
  serializedDirectories = map (
    directory:
    lib.filterAttrs (_: value: value != null) {
      name = directory.name;
      priority = directory.priority;
      storage = directory.storage;
      download_path = directory.downloadPath;
      media_type = directory.mediaType;
      media_category = directory.mediaCategory;
      download_type_folder = directory.downloadTypeFolder;
      download_category_folder = directory.downloadCategoryFolder;
      monitor_type = directory.monitorType;
      monitor_mode = directory.monitorMode;
      transfer_type = directory.transferType;
      overwrite_mode = directory.overwriteMode;
      library_path = directory.libraryPath;
      library_storage = directory.libraryStorage;
      renaming = directory.renaming;
      scraping = directory.scraping;
      notify = directory.notify;
      library_type_folder = directory.libraryTypeFolder;
      library_category_folder = directory.libraryCategoryFolder;
    }
  ) cfg.directories;
  serializedMediaServers = map (
    mediaServer:
    (builtins.removeAttrs mediaServer [ "syncLibraries" ])
    // {
      sync_libraries = mediaServer.syncLibraries;
    }
  ) cfg.mediaServers;
  serializedStorages = cfg.storages;

  serializeEnv = value:
    if builtins.isBool value then lib.boolToString value
    else if builtins.isInt value || builtins.isFloat value then toString value
    else toString value;

  mkSeedSystemConfigService =
    {
      description,
      configKey,
      serializedConfig,
      updatedMessage,
      unchangedMessage,
    }:
    {
      inherit description;
      before = [ "moviepilot-backend.service" ];
      requires = [ "moviepilot-prepare.service" ];
      after = [ "moviepilot-prepare.service" ];
      environment = backendEnv;
      serviceConfig =
        {
          Type = "oneshot";
          WorkingDirectory = "${runtimeDir}/backend";
          User = cfg.user;
          Group = cfg.group;
          UMask = "0027";
        }
        // configSeedHardening
        // optionalAttrs (cfg.environmentFile != null) {
          EnvironmentFile = cfg.environmentFile;
        };
      script = ''
        set -euo pipefail

        ${cfg.pythonPackage}/bin/python - <<'PY'
        import json
        import os

        from app.db.systemconfig_oper import SystemConfigOper
        from app.schemas.types import SystemConfigKey

        desired = json.loads(${serializeJsonForPython serializedConfig})

        for entry in desired:
            config_from_environment = entry.pop("configFromEnvironment", None) or {}
            if not config_from_environment:
                continue

            config = dict(entry.get("config", {}))
            for key, env_name in config_from_environment.items():
                if env_name not in os.environ:
                    name = entry.get("name") or entry.get("type") or "unknown"
                    raise RuntimeError(
                        f"Missing environment variable {env_name} for {name}.{key}"
                    )
                config[key] = os.environ[env_name]
            entry["config"] = config

        oper = SystemConfigOper()
        current = oper.get(SystemConfigKey.${configKey})
        if current != desired:
            oper.set(SystemConfigKey.${configKey}, desired)
            print(${builtins.toJSON updatedMessage})
        else:
            print(${builtins.toJSON unchangedMessage})
        PY
      '';
    };

  backendEnv = {
    CONFIG_DIR = "${cfg.stateDir}/config";
    HOME = cfg.stateDir;
    HOST = cfg.host;
    PORT = toString cfg.backend.port;
    NGINX_PORT = toString publicPort;
    TZ = cfg.timeZone;
    PLAYWRIGHT_BROWSERS_PATH = resolvedPlaywrightBrowsersPath;
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    PYTHONDONTWRITEBYTECODE = "1";
    PYTHONNOUSERSITE = "1";
    PYTHONPATH = "${runtimeDir}/backend";
    PYTHONUNBUFFERED = "1";
    MOVIEPILOT_NIX_PURE = "1";
  } // lib.mapAttrs (_: value: serializeEnv value) effectiveSettings;

  frontendEnv = {
    NGINX_PORT = toString cfg.frontend.port;
    PORT = toString cfg.backend.port;
  };

  commonHardening = {
    KeyringMode = "private";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateIPC = true;
    PrivateMounts = true;
    PrivateTmp = true;
    ProcSubset = "pid";
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectProc = "invisible";
    ProtectSystem = "strict";
    RemoveIPC = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
  } // optionalAttrs (!stateDirDisablesProtectHome) {
    ProtectHome = true;
  };

  mkRuntimeHardening = readWritePaths:
    commonHardening
    // {
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";
    }
    // optionalAttrs (readWritePaths != [ ]) {
      ReadWritePaths = readWritePaths;
    };

  prepareHardening = (mkRuntimeHardening prepareReadWritePaths) // {
    IPAddressDeny = "any";
    MemoryDenyWriteExecute = true;
    PrivateDevices = true;
    RestrictAddressFamilies = [ "AF_UNIX" ];
    SystemCallErrorNumber = "EPERM";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "~@resources"
    ];
  };

  backendHardening = (mkRuntimeHardening backendReadWritePaths) // {
    # MoviePilot dashboard reads host-wide CPU/memory/network metrics via psutil.
    ProcSubset = "all";
    PrivateDevices = !backendUsesWhitelistedDevices;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
  } // optionalAttrs backendUsesWhitelistedDevices {
    DeviceAllow = backendDeviceAllow;
    DevicePolicy = "closed";
  };
  frontendHardening = (mkRuntimeHardening [ ]) // {
    PrivateDevices = true;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
  };
  configSeedHardening = (mkRuntimeHardening [ ]) // {
    PrivateDevices = true;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
  };
in
{
  options.services.moviepilot = {
    enable = mkEnableOption "MoviePilot";

    backendPackage = mkOption {
      type = types.package;
      default = packages.moviepilot-backend;
    };

    pluginsPackage = mkOption {
      type = types.package;
      default = packages.moviepilot-plugins;
    };

    resourcesPackage = mkOption {
      type = types.package;
      default = packages.moviepilot-resources;
    };

    frontendPackage = mkOption {
      type = types.package;
      default = packages.moviepilot-frontend;
    };

    pythonPackage = mkOption {
      type = types.package;
      default = packages.moviepilot-python;
    };

    playwrightBrowsersPath = mkOption {
      type = types.oneOf [
        types.package
        types.path
        types.str
      ];
      default = defaultPlaywrightBrowsersPath;
      example = literalExpression "pkgs.playwright-driver.browsers";
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
      default = if cfg.frontend.enable then "127.0.0.1" else "0.0.0.0";
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
      type = types.attrsOf scalarValueType;
      default = { };
      example = literalExpression ''
        {
          SUPERUSER = "admin";
          DB_TYPE = "sqlite";
        }
      '';
    };

    downloaders = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              example = "qBittorrent";
            };

            type = mkOption {
              type = types.str;
              example = "qbittorrent";
            };

            default = mkOption {
              type = types.bool;
              default = false;
            };

            enabled = mkOption {
              type = types.bool;
              default = true;
            };

            config = mkOption {
              type = types.attrsOf scalarValueType;
              default = { };
              example = literalExpression ''
                {
                  host = "127.0.0.1";
                  port = 8080;
                  username = "admin";
                }
              '';
            };

            configFromEnvironment = mkOption {
              type = types.attrsOf types.str;
              default = { };
              example = literalExpression ''
                {
                  password = "QBITTORRENT_PASSWORD";
                }
              '';
            };

            pathMapping = mkOption {
              type = types.listOf (
                types.submodule {
                  options = {
                    source = mkOption {
                      type = types.str;
                    };

                    target = mkOption {
                      type = types.str;
                    };
                  };
                }
              );
              default = [ ];
              example = literalExpression ''
                [
                  {
                    source = "/data/shared/qBittorrent/downloads";
                    target = "/data/shared/qBittorrent/downloads";
                  }
                ]
              '';
            };
          };
        }
      );
      default = [ ];
      example = literalExpression ''
        [
          {
            name = "qBittorrent";
            type = "qbittorrent";
            default = true;
            config = {
              host = "127.0.0.1";
              port = 8080;
              username = "admin";
            };
            configFromEnvironment = {
              password = "QBITTORRENT_PASSWORD";
            };
            pathMapping = [
              {
                source = "/data/shared/qBittorrent/downloads";
                target = "/data/shared/qBittorrent/downloads";
              }
            ];
          }
        ]
      '';
    };

    directories = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              example = "本地整理";
            };

            priority = mkOption {
              type = types.int;
              default = 0;
            };

            storage = mkOption {
              type = types.str;
              default = "local";
            };

            downloadPath = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "/data/shared/qBittorrent/downloads";
            };

            mediaType = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "电影";
            };

            mediaCategory = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "国漫";
            };

            downloadTypeFolder = mkOption {
              type = types.bool;
              default = false;
            };

            downloadCategoryFolder = mkOption {
              type = types.bool;
              default = false;
            };

            monitorType = mkOption {
              type = types.nullOr (types.enum [
                "downloader"
                "monitor"
              ]);
              default = null;
            };

            monitorMode = mkOption {
              type = types.enum [
                "fast"
                "compatibility"
              ];
              default = "fast";
            };

            transferType = mkOption {
              type = types.nullOr (types.enum [
                "move"
                "copy"
                "link"
                "softlink"
              ]);
              default = null;
            };

            overwriteMode = mkOption {
              type = types.nullOr (types.enum [
                "always"
                "size"
                "never"
                "latest"
              ]);
              default = null;
            };

            libraryPath = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "/data/shared/media";
            };

            libraryStorage = mkOption {
              type = types.nullOr types.str;
              default = "local";
            };

            renaming = mkOption {
              type = types.bool;
              default = false;
            };

            scraping = mkOption {
              type = types.bool;
              default = false;
            };

            notify = mkOption {
              type = types.bool;
              default = true;
            };

            libraryTypeFolder = mkOption {
              type = types.bool;
              default = false;
            };

            libraryCategoryFolder = mkOption {
              type = types.bool;
              default = false;
            };
          };
        }
      );
      default = [ ];
      example = literalExpression ''
        [
          {
            name = "本地整理";
            storage = "local";
            downloadPath = "/data/shared/qBittorrent/downloads";
            monitorType = "downloader";
            transferType = "link";
            libraryPath = "/data/shared/media";
            libraryStorage = "local";
            renaming = true;
            scraping = true;
            libraryTypeFolder = true;
          }
        ]
      '';
    };

    mediaServers = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              example = "Jellyfin";
            };

            type = mkOption {
              type = types.str;
              example = "jellyfin";
            };

            enabled = mkOption {
              type = types.bool;
              default = true;
            };

            config = mkOption {
              type = types.attrsOf scalarValueType;
              default = { };
              example = literalExpression ''
                {
                  host = "http://127.0.0.1:8096";
                }
              '';
            };

            configFromEnvironment = mkOption {
              type = types.attrsOf types.str;
              default = { };
              example = literalExpression ''
                {
                  apikey = "JELLYFIN_API_KEY";
                }
              '';
            };

            syncLibraries = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "fb523da49904969939890997b679d34d" ];
            };
          };
        }
      );
      default = [ ];
      example = literalExpression ''
        [
          {
            name = "Jellyfin";
            type = "jellyfin";
            config = {
              host = "http://127.0.0.1:8096";
            };
            configFromEnvironment = {
              apikey = "JELLYFIN_API_KEY";
            };
            syncLibraries = [ "fb523da49904969939890997b679d34d" ];
          }
        ]
      '';
    };

    storages = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              example = "本地";
            };

            type = mkOption {
              type = types.str;
              example = "local";
            };

            config = mkOption {
              type = types.attrsOf scalarValueType;
              default = { };
              example = literalExpression ''
                {
                  host = "http://127.0.0.1:5244";
                  username = "admin";
                }
              '';
            };

            configFromEnvironment = mkOption {
              type = types.attrsOf types.str;
              default = { };
              example = literalExpression ''
                {
                  password = "OPENLIST_PASSWORD";
                }
              '';
            };
          };
        }
      );
      default = [ ];
      example = literalExpression ''
        [
          {
            name = "本地";
            type = "local";
          }
          {
            name = "OpenList";
            type = "alist";
            config = {
              host = "http://127.0.0.1:5244";
              username = "admin";
            };
            configFromEnvironment = {
              password = "OPENLIST_PASSWORD";
            };
          }
        ]
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

    backend.allowedDevices = mkOption {
      type = types.listOf (types.oneOf [
        types.str
        (types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              example = "/dev/dri/renderD128";
            };

            permissions = mkOption {
              type = types.enum [
                "r"
                "rw"
                "rwm"
              ];
              default = "rw";
            };
          };
        })
      ]);
      default = [ ];
      apply = map normalizeAllowedDevice;
      example = literalExpression ''
        [
          {
            path = "/dev/dri/renderD128";
            permissions = "rw";
          }
          {
            path = "/dev/video0";
            permissions = "r";
          }
        ]
      '';
    };

    backend.supplementaryGroups = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = literalExpression ''
        [
          "render"
          "video"
        ]
      '';
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
    assertions = [
      {
        assertion = conflictingSettingNames == [ ];
        message =
          "services.moviepilot.settings 不能覆盖模块保留环境变量: "
          + lib.concatStringsSep ", " conflictingSettingNames;
      }
      {
        assertion = lib.hasPrefix "/" cfg.stateDir;
        message = "services.moviepilot.stateDir 必须是绝对路径";
      }
      {
        assertion = !stateDirInStore;
        message = "services.moviepilot.stateDir 不能位于 /nix/store；该路径只读，无法作为运行时状态目录";
      }
      {
        assertion = cfg.environmentFile == null || lib.hasPrefix "/" cfg.environmentFile;
        message = "services.moviepilot.environmentFile 必须是绝对路径";
      }
      {
        assertion = !(cfg.frontend.enable && cfg.backend.port == cfg.frontend.port);
        message = "services.moviepilot.backend.port 与 services.moviepilot.frontend.port 不能相同";
      }
      {
        assertion = !(builtins.isString cfg.playwrightBrowsersPath) || lib.hasPrefix "/" cfg.playwrightBrowsersPath;
        message = "services.moviepilot.playwrightBrowsersPath 若使用字符串，必须是绝对路径";
      }
      {
        assertion = builtins.all (path: lib.hasPrefix "/dev/" path) backendWhitelistedDevices;
        message = "services.moviepilot.backend.allowedDevices 必须是 /dev/ 下的绝对设备路径列表";
      }
    ];

    warnings =
      optional (cfg.user == "root" || cfg.group == "root")
        "services.moviepilot 最好不要以 root 用户或 root 组运行。"
      ++ optional (backendUsesWhitelistedDevices && backendNeedsRenderGroup && !(lib.elem "render" backendSupplementaryGroups))
        "services.moviepilot.backend.allowedDevices 包含 /dev/dri 设备，但 services.moviepilot.backend.supplementaryGroups 未包含 render；很多系统上设备节点仍会因权限被拒绝访问。"
      ++ optional (backendUsesWhitelistedDevices && backendNeedsVideoGroup && !(lib.elem "video" backendSupplementaryGroups))
        "services.moviepilot.backend.allowedDevices 包含 /dev/video* 设备，但 services.moviepilot.backend.supplementaryGroups 未包含 video；很多系统上设备节点仍会因权限被拒绝访问。"
      ++ optional (backendDuplicateOnlyAllowedDevicePaths != [ ])
        (
          "services.moviepilot.backend.allowedDevices 包含重复设备路径；模块会自动按路径去重: "
          + lib.concatStringsSep ", " backendDuplicateOnlyAllowedDevicePaths
        )
      ++ optional (backendConflictingAllowedDeviceSummaries != [ ])
        (
          "services.moviepilot.backend.allowedDevices 对同一路径声明了不同 permissions；模块会自动收敛到更宽权限: "
          + lib.concatStringsSep ", " backendConflictingAllowedDeviceSummaries
        )
      ++ optional stateDirDisablesProtectHome
        "services.moviepilot.stateDir 位于 /home、/root 或 /run/user 下，模块会自动禁用 ProtectHome；建议改用 /var/lib/moviepilot 或 /srv/moviepilot。"
      ++ optional environmentFileInStore
        "services.moviepilot.environmentFile 指向 /nix/store；这通常意味着密钥被固化进 store。更推荐使用 sops-nix、agenix 或 /run/secrets 下的文件。";

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
      "z ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      "Z ${cfg.stateDir}/config 0750 ${cfg.user} ${cfg.group} -"
      "Z ${cfg.stateDir}/runtime 0750 ${cfg.user} ${cfg.group} -"
    ];

    networking.firewall.allowedTCPPorts = optionals cfg.openFirewall [ publicPort ];

    systemd.services.moviepilot-prepare = {
      description = "Prepare MoviePilot runtime tree";
      path = with pkgs; [
        coreutils
        findutils
        rsync
      ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0027";
      } // prepareHardening;
      script = ''
        set -euo pipefail

        runtime_dir=${runtimeDir}
        backend_dir=$runtime_dir/backend
        frontend_link=$runtime_dir/frontend
        backend_marker=$runtime_dir/.backend-package
        resources_dir=$backend_dir/app/helper
        plugins_dir=${cfg.stateDir}/config/plugins
        plugins_manifest=${cfg.stateDir}/config/.packaged-plugins
        plugins_marker=${cfg.stateDir}/config/.plugins-package
        resources_manifest=${cfg.stateDir}/config/.packaged-resources
        resources_marker=${cfg.stateDir}/config/.resources-package
        backend_source_dir=${backendSourceDir}
        plugins_source_dir=${pluginsSourceDir}
        plugins_manifest_source=${pluginsManifestSource}
        resources_source_dir=${resourcesSourceDir}
        resources_manifest_source=${resourcesManifestSource}
        current_backend_package=${backendPackage}
        current_plugins_package=${pluginsPackage}
        current_resources_package=${resourcesPackage}
        backend_refresh=0
        plugins_refresh=0
        resources_refresh=0

        install -d -m 0750 "$runtime_dir" "$backend_dir" "$plugins_dir" "$resources_dir"

        if [ ! -d "$plugins_source_dir" ]; then
          echo "错误: 找不到插件源码目录: $plugins_source_dir" >&2
          exit 1
        fi

        if [ ! -d "$resources_source_dir" ]; then
          echo "错误: 找不到资源源码目录: $resources_source_dir" >&2
          exit 1
        fi

        if [ ! -f "$backend_marker" ] \
          || [ "$(cat "$backend_marker")" != "$current_backend_package" ] \
          || [ ! -f "$backend_dir/app/main.py" ]; then
          backend_refresh=1
          rsync -a --delete \
            --exclude 'app/plugins/' \
            --exclude '__pycache__/' \
            --exclude '*.pyc' \
            "$backend_source_dir/" "$backend_dir/"

          chmod -R u+w "$backend_dir"

          printf '%s' "$current_backend_package" > "$backend_marker"
          chmod -R u+rwX,go-rwx "$backend_dir"
          chmod 0640 "$backend_marker"
        fi

        if [ "$backend_refresh" -eq 1 ] \
          || [ ! -f "$plugins_marker" ] \
          || [ "$(cat "$plugins_marker")" != "$current_plugins_package" ] \
          || [ ! -f "$plugins_manifest" ] \
          || [ ! -f "$plugins_dir/__init__.py" ]; then
          plugins_refresh=1
        fi

        if [ "$plugins_refresh" -eq 1 ]; then
          if [ -f "$plugins_manifest" ]; then
            while IFS= read -r packaged_entry; do
              [ -n "$packaged_entry" ] || continue
              rm -rf "$plugins_dir/$packaged_entry"
            done < "$plugins_manifest"
          fi

          rsync -a "$plugins_source_dir/" "$plugins_dir/"
          if [ -f "$plugins_manifest_source" ]; then
            cp "$plugins_manifest_source" "$plugins_manifest"
          else
            find "$plugins_source_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$plugins_manifest"
          fi
          printf '%s' "$current_plugins_package" > "$plugins_marker"
          chmod -R u+rwX,go-rwx "$plugins_dir"
          chmod 0640 "$plugins_manifest"
          chmod 0640 "$plugins_marker"
        fi

        if [ "$backend_refresh" -eq 1 ] \
          || [ ! -f "$resources_marker" ] \
          || [ "$(cat "$resources_marker")" != "$current_resources_package" ] \
          || [ ! -f "$resources_manifest" ] \
          || [ ! -e "$resources_dir/user.sites.v2.bin" ]; then
          resources_refresh=1
        fi

        if [ "$resources_refresh" -eq 1 ]; then
          if [ -f "$resources_manifest" ]; then
            while IFS= read -r packaged_entry; do
              [ -n "$packaged_entry" ] || continue
              rm -rf "$resources_dir/$packaged_entry"
            done < "$resources_manifest"
          fi

          rsync -a "$resources_source_dir/" "$resources_dir/"
          if [ -f "$resources_manifest_source" ]; then
            cp "$resources_manifest_source" "$resources_manifest"
          else
            find "$resources_source_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort > "$resources_manifest"
          fi
          printf '%s' "$current_resources_package" > "$resources_marker"
          chmod -R u+rwX,go-rwx "$resources_dir"
          chmod 0640 "$resources_manifest"
          chmod 0640 "$resources_marker"
        fi

        if [ "$(readlink "$backend_dir/app/plugins" 2>/dev/null || true)" != "$plugins_dir" ]; then
          rm -rf "$backend_dir/app/plugins"
          ln -s "$plugins_dir" "$backend_dir/app/plugins"
        fi

        ${optionalString cfg.frontend.enable ''
          frontend_target=${cfg.frontendPackage}/share/moviepilot/frontend
          if [ "$(readlink "$frontend_link" 2>/dev/null || true)" != "$frontend_target" ]; then
            rm -rf "$frontend_link"
            ln -s "$frontend_target" "$frontend_link"
          fi
        ''}

        ${optionalString (!cfg.frontend.enable) ''
          if [ -L "$frontend_link" ] || [ -e "$frontend_link" ]; then
            rm -rf "$frontend_link"
          fi
        ''}
      '';
    };

    systemd.services.moviepilot-seed-downloaders = mkIf downloadersConfigured (
      mkSeedSystemConfigService {
        description = "Seed MoviePilot downloaders";
        configKey = "Downloaders";
        serializedConfig = serializedDownloaders;
        updatedMessage = "MoviePilot downloaders config updated";
        unchangedMessage = "MoviePilot downloaders config already up to date";
      }
    );

    systemd.services.moviepilot-seed-directories = mkIf directoriesConfigured (
      mkSeedSystemConfigService {
        description = "Seed MoviePilot directories";
        configKey = "Directories";
        serializedConfig = serializedDirectories;
        updatedMessage = "MoviePilot directories config updated";
        unchangedMessage = "MoviePilot directories config already up to date";
      }
    );

    systemd.services.moviepilot-seed-media-servers = mkIf mediaServersConfigured (
      mkSeedSystemConfigService {
        description = "Seed MoviePilot media servers";
        configKey = "MediaServers";
        serializedConfig = serializedMediaServers;
        updatedMessage = "MoviePilot media servers config updated";
        unchangedMessage = "MoviePilot media servers config already up to date";
      }
    );

    systemd.services.moviepilot-seed-storages = mkIf storagesConfigured (
      mkSeedSystemConfigService {
        description = "Seed MoviePilot storages";
        configKey = "Storages";
        serializedConfig = serializedStorages;
        updatedMessage = "MoviePilot storages config updated";
        unchangedMessage = "MoviePilot storages config already up to date";
      }
    );

    systemd.services.moviepilot-backend = {
      description = "MoviePilot backend";
      wantedBy = [ "multi-user.target" ];
      requires =
        [ "moviepilot-prepare.service" ]
        ++ optionals downloadersConfigured [ "moviepilot-seed-downloaders.service" ]
        ++ optionals directoriesConfigured [ "moviepilot-seed-directories.service" ]
        ++ optionals mediaServersConfigured [ "moviepilot-seed-media-servers.service" ]
        ++ optionals storagesConfigured [ "moviepilot-seed-storages.service" ];
      after =
        [ "moviepilot-prepare.service" ]
        ++ optionals downloadersConfigured [ "moviepilot-seed-downloaders.service" ]
        ++ optionals directoriesConfigured [ "moviepilot-seed-directories.service" ]
        ++ optionals mediaServersConfigured [ "moviepilot-seed-media-servers.service" ]
        ++ optionals storagesConfigured [ "moviepilot-seed-storages.service" ];
      path = cfg.extraPackages;
      environment = backendEnv;
      serviceConfig = {
        ExecStart = "${cfg.pythonPackage}/bin/python -m app.main";
        WorkingDirectory = "${runtimeDir}/backend";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "10s";
      }
      // backendHardening
      // optionalAttrs (backendSupplementaryGroups != [ ]) {
        SupplementaryGroups = backendSupplementaryGroups;
      }
      // optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
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
      environment = frontendEnv;
      serviceConfig = {
        ExecStart = "${pkgs.nodejs_20}/bin/node service.js";
        WorkingDirectory = "${runtimeDir}/frontend/dist";
        User = cfg.user;
        Group = cfg.group;
        UMask = "0027";
        Restart = "on-failure";
        RestartSec = "10s";
      } // frontendHardening;
    };
  };
}
