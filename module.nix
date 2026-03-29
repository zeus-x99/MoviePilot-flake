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
  backendDirectoryReadWritePaths =
    lib.unique (
      builtins.filter (
        path: builtins.isString path && path != "" && lib.hasPrefix "/" path
      ) (
        lib.flatten (
          map (
            directory:
            (lib.optional (directory.downloadPath != null) directory.downloadPath)
            ++ (lib.optional (directory.libraryPath != null) directory.libraryPath)
          ) cfg.directories
        )
      )
    );
  sandboxRootInStore = cfg.sandboxRoot != null && pathIsEqualOrUnder "/nix/store" cfg.sandboxRoot;
  backendPathsOutsideSandboxRoot =
    if cfg.sandboxRoot == null then
      [ ]
    else
      builtins.filter (
        path: !(pathIsEqualOrUnder cfg.sandboxRoot path)
      ) backendDirectoryReadWritePaths;
  backendReadWritePaths =
    [ "${cfg.stateDir}/config" ]
    ++ (
      if cfg.sandboxRoot != null then
        [ cfg.sandboxRoot ]
      else
        backendDirectoryReadWritePaths
    );
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  backendPackage = cfg.backendPackage;
  pluginsPackage = cfg.pluginsPackage;
  resourcesPackage = cfg.resourcesPackage;
  backendSourceDir = "${backendPackage}/share/moviepilot/backend";
  pluginsSourceDir = "${pluginsPackage}/share/moviepilot/plugins";
  pluginsManifestSource = "${pluginsPackage}/share/moviepilot/plugins-manifest";
  resourcesSourceDir = "${resourcesPackage}/share/moviepilot/resources";
  resourcesManifestSource = "${resourcesPackage}/share/moviepilot/resources-manifest";
  postgresqlCfg = cfg.database.postgresql;
  redisCfg = cfg.cache.redis;
  apiSeedTokenConfigured = cfg.environmentFile != null || effectiveSettings ? API_TOKEN;
  superuserPasswordSeedConfigured = cfg.environmentFile != null || effectiveSettings ? SUPERUSER_PASSWORD;
  redisUrl = "redis://${redisCfg.host}:${toString redisCfg.port}/${toString redisCfg.database}";
  managedDirectoryTmpfilesRules = builtins.concatLists (
    map (
      directory: [
        "d ${directory.path} ${directory.mode} ${directory.user} ${directory.group} -"
        "${if directory.recursive then "Z" else "z"} ${directory.path} ${directory.mode} ${directory.user} ${directory.group} -"
      ]
    ) cfg.managedDirectories
  );
  defaultSettings = {
    AUTO_UPDATE_RESOURCE = false;
  }
  // optionalAttrs postgresqlCfg.enable {
    DB_TYPE = "postgresql";
    DB_POSTGRESQL_HOST = postgresqlCfg.host;
    DB_POSTGRESQL_PORT = postgresqlCfg.port;
    DB_POSTGRESQL_DATABASE = postgresqlCfg.database;
    DB_POSTGRESQL_USERNAME = postgresqlCfg.user;
  }
  // optionalAttrs (postgresqlCfg.enable && postgresqlCfg.password != null) {
    DB_POSTGRESQL_PASSWORD = postgresqlCfg.password;
  }
  // optionalAttrs redisCfg.enable {
    CACHE_BACKEND_TYPE = "redis";
    CACHE_BACKEND_URL = redisUrl;
  };
  effectiveSettings = defaultSettings // cfg.settings;
  scalarValueType = types.oneOf [
    types.bool
    types.float
    types.int
    types.str
  ];
  jsonValueType = types.nullOr (
    types.oneOf [
      scalarValueType
      (types.listOf jsonValueType)
      (types.attrsOf jsonValueType)
    ]
  );
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
  downloadersConfigured = cfg.downloaders != [ ];
  directoriesConfigured = cfg.directories != [ ];
  mediaServersConfigured = cfg.mediaServers != [ ];
  storagesConfigured = cfg.storages != [ ];
  sitesConfigured = cfg.sites != null;
  siteAuthConfigured = cfg.siteAuth != null;
  subscriptionsConfigured = cfg.subscriptions != null;
  indexerSitesConfigured = cfg.indexerSites != null;
  rssSitesConfigured = cfg.rssSites != null;
  installedPluginsConfigured = cfg.installedPlugins != null;
  pluginConfigsConfigured = cfg.pluginConfigs != null;
  pluginFoldersConfigured = cfg.pluginFolders != null;
  apiSeedConfigured =
    superuserPasswordSeedConfigured
    || downloadersConfigured
    || directoriesConfigured
    || mediaServersConfigured
    || storagesConfigured
    || sitesConfigured
    || siteAuthConfigured
    || subscriptionsConfigured
    || indexerSitesConfigured
    || rssSitesConfigured
    || installedPluginsConfigured
    || pluginConfigsConfigured
    || pluginFoldersConfigured;
  apiBaseUrl = "http://127.0.0.1:${toString cfg.backend.port}/api/v1";
  configuredSeedServiceUnits =
    optionals superuserPasswordSeedConfigured [ "moviepilot-seed-superuser-password.service" ]
    ++ optionals downloadersConfigured [ "moviepilot-seed-downloaders.service" ]
    ++ optionals directoriesConfigured [ "moviepilot-seed-directories.service" ]
    ++ optionals mediaServersConfigured [ "moviepilot-seed-media-servers.service" ]
    ++ optionals storagesConfigured [ "moviepilot-seed-storages.service" ]
    ++ optionals installedPluginsConfigured [ "moviepilot-seed-installed-plugins.service" ]
    ++ optionals pluginConfigsConfigured [ "moviepilot-seed-plugin-configs.service" ]
    ++ optionals pluginFoldersConfigured [ "moviepilot-seed-plugin-folders.service" ]
    ++ optionals sitesConfigured [ "moviepilot-seed-sites.service" ]
    ++ optionals siteAuthConfigured [ "moviepilot-seed-site-auth.service" ]
    ++ optionals subscriptionsConfigured [ "moviepilot-seed-subscriptions.service" ]
    ++ optionals indexerSitesConfigured [ "moviepilot-seed-indexer-sites.service" ]
    ++ optionals rssSitesConfigured [ "moviepilot-seed-rss-sites.service" ];
  frontendSeedServiceUnits = configuredSeedServiceUnits;
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
  serializedSites =
    if cfg.sites == null then
      [ ]
    else
      map (
        site:
        lib.filterAttrs (_: value: value != null) {
          name = site.name;
          domain = site.domain;
          url = site.url;
          pri = site.priority;
          rss = site.rss;
          cookie = site.cookie;
          ua = site.userAgent;
          apikey = site.apikey;
          token = site.token;
          proxy = if site.proxy then 1 else 0;
          filter = site.filter;
          render = if site.render then 1 else 0;
          public =
            if site.public == null then
              null
            else if site.public then
              1
            else
              0;
          timeout = site.timeout;
          limit_interval = site.limitInterval;
          limit_count = site.limitCount;
          limit_seconds = site.limitSeconds;
          is_active = site.enabled;
          downloader = site.downloader;
          fromEnvironment = site.fromEnvironment;
        }
      ) cfg.sites;
  serializedSiteAuth =
    if cfg.siteAuth == null then
      null
    else
      {
        site = cfg.siteAuth.site;
        params = cfg.siteAuth.params;
        paramsFromEnvironment = cfg.siteAuth.paramsFromEnvironment;
      };
  serializedSubscriptions =
    if cfg.subscriptions == null then
      [ ]
    else
      map (
        subscription:
        lib.filterAttrs (_: value: value != null) {
          name = subscription.name;
          year = subscription.year;
          type = subscription.type;
          keyword = subscription.keyword;
          tmdbid = subscription.tmdbid;
          doubanid = subscription.doubanid;
          bangumiid = subscription.bangumiid;
          mediaid = subscription.mediaId;
          season = subscription.season;
          filter = subscription.filter;
          include = subscription.include;
          exclude = subscription.exclude;
          quality = subscription.quality;
          resolution = subscription.resolution;
          effect = subscription.effect;
          total_episode = subscription.totalEpisode;
          start_episode = subscription.startEpisode;
          sites = subscription.sites;
          downloader = subscription.downloader;
          best_version = if subscription.bestVersion then 1 else 0;
          save_path = subscription.savePath;
          search_imdbid = if subscription.searchImdbId then 1 else 0;
          custom_words = subscription.customWords;
          media_category = subscription.mediaCategory;
          filter_groups = subscription.filterGroups;
          episode_group = subscription.episodeGroup;
          state = subscription.state;
          username = subscription.username;
        }
      ) cfg.subscriptions;
  serializedIndexerSites = if cfg.indexerSites == null then [ ] else cfg.indexerSites;
  serializedRssSites = if cfg.rssSites == null then [ ] else cfg.rssSites;
  serializedInstalledPlugins = if cfg.installedPlugins == null then [ ] else lib.unique cfg.installedPlugins;
  serializedPluginConfigs = if cfg.pluginConfigs == null then { } else cfg.pluginConfigs;
  serializedPluginFolders =
    if cfg.pluginFolders == null then
      { }
    else
      lib.mapAttrs (
        _: folder:
        if builtins.isList folder then
          folder
        else
          lib.filterAttrs (_: value: value != null) {
            plugins = folder.plugins;
            order = folder.order;
            icon = folder.icon;
          }
      ) cfg.pluginFolders;

  serializeEnv = value:
    if builtins.isBool value then lib.boolToString value
    else if builtins.isInt value || builtins.isFloat value then toString value
    else toString value;

  mkSeedApiService =
    {
      description,
      mode,
      payload,
      requires ? [ ],
      after ? [ ],
      environment ? { },
    }:
    {
      inherit description;
      wantedBy = [ "multi-user.target" ];
      partOf = [ "moviepilot-backend.service" ];
      before = optionals cfg.frontend.enable [ "moviepilot-frontend.service" ];
      requires = [ "moviepilot-backend.service" ] ++ requires;
      after = [ "moviepilot-backend.service" ] ++ after;
      restartIfChanged = true;
      environment =
        backendEnv
        // {
          MOVIEPILOT_API_BASE_URL = apiBaseUrl;
        }
        // environment;
      serviceConfig =
        {
          Type = "oneshot";
          RemainAfterExit = true;
          WorkingDirectory = "${runtimeDir}/backend";
          User = cfg.user;
          Group = cfg.group;
          UMask = "0027";
        }
        // (mkRuntimeHardening [ "${cfg.stateDir}/config" ])
        // {
          PrivateDevices = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        }
        // optionalAttrs (cfg.environmentFile != null) {
          EnvironmentFile = cfg.environmentFile;
        };
      script = ''
        set -euo pipefail

        ${cfg.pythonPackage}/bin/python ${./nix/moviepilot-api-seed.py} ${mode} <<'JSON'
        ${builtins.toJSON payload}
        JSON
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
    PrivateDevices = true;
    RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
    ];
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

    sandboxRoot = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/data/shared";
      description = ''
        后端服务需要读写的共同父目录。设置后，模块会在 systemd 沙箱里只暴露这个根目录，
        而不是分别暴露各个下载目录和媒体库目录。这样可以避免硬链接整理时因为多个
        bind mount 落在不同挂载点而触发 "Invalid cross-device link"。
      '';
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

    database.postgresql = {
      enable = mkEnableOption "use PostgreSQL as the MoviePilot database backend";

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
      };

      database = mkOption {
        type = types.str;
        default = "moviepilot";
      };

      user = mkOption {
        type = types.str;
        default = "moviepilot";
      };

      password = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };

    cache.redis = {
      enable = mkEnableOption "use Redis as the MoviePilot cache backend";

      host = mkOption {
        type = types.str;
        default = "127.0.0.1";
      };

      port = mkOption {
        type = types.port;
        default = 6379;
      };

      database = mkOption {
        type = types.int;
        default = 0;
      };
    };

    managedDirectories = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            path = mkOption {
              type = types.str;
              example = "/data/shared/media";
            };

            user = mkOption {
              type = types.str;
              default = cfg.user;
            };

            group = mkOption {
              type = types.str;
              default = cfg.group;
            };

            mode = mkOption {
              type = types.str;
              default = "0755";
            };

            recursive = mkOption {
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
            path = "/data/shared/media";
          }
        ]
      '';
      description = ''
        额外需要由 systemd-tmpfiles 创建并校正权限的目录。默认会使用
        services.moviepilot.user/group 作为属主属组。
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

    sites = mkOption {
      type = types.nullOr (
        types.listOf (
          types.submodule {
            options = {
              domain = mkOption {
                type = types.str;
                example = "pthome.net";
              };

              url = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "https://pthome.net/";
              };

              name = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "馒头";
              };

              priority = mkOption {
                type = types.int;
                default = 0;
              };

              rss = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              cookie = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              userAgent = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              apikey = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              token = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              fromEnvironment = mkOption {
                type = types.attrsOf types.str;
                default = { };
                example = literalExpression ''
                  {
                    cookie = "MTEAM_COOKIE";
                  }
                '';
              };

              proxy = mkOption {
                type = types.bool;
                default = false;
              };

              filter = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              render = mkOption {
                type = types.bool;
                default = false;
              };

              public = mkOption {
                type = types.nullOr types.bool;
                default = null;
              };

              timeout = mkOption {
                type = types.int;
                default = 15;
              };

              limitInterval = mkOption {
                type = types.nullOr types.int;
                default = null;
              };

              limitCount = mkOption {
                type = types.nullOr types.int;
                default = null;
              };

              limitSeconds = mkOption {
                type = types.nullOr types.int;
                default = null;
              };

              enabled = mkOption {
                type = types.bool;
                default = true;
              };

              downloader = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
            };
          }
        )
      );
      default = null;
      example = literalExpression ''
        [
          {
            domain = "m-team.io";
            url = "https://m-team.io/";
            fromEnvironment = {
              cookie = "MTEAM_COOKIE";
            };
          }
        ]
      '';
    };

    siteAuth = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            site = mkOption {
              type = types.str;
              example = "iyuu";
            };

            params = mkOption {
              type = types.attrsOf scalarValueType;
              default = { };
            };

            paramsFromEnvironment = mkOption {
              type = types.attrsOf types.str;
              default = { };
              example = literalExpression ''
                {
                  token = "IYUU_SITE_TOKEN";
                }
              '';
            };
          };
        }
      );
      default = null;
      example = literalExpression ''
        {
          site = "iyuu";
          paramsFromEnvironment = {
            token = "IYUU_SITE_TOKEN";
          };
        }
      '';
    };

    subscriptions = mkOption {
      type = types.nullOr (
        types.listOf (
          types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                example = "斗破苍穹";
              };

              year = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "2017";
              };

              type = mkOption {
                type = types.enum [
                  "电影"
                  "电视剧"
                ];
                example = "电视剧";
              };

              keyword = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "Fights Break Sphere S05";
              };

              tmdbid = mkOption {
                type = types.nullOr types.int;
                default = null;
                example = 79481;
              };

              doubanid = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              bangumiid = mkOption {
                type = types.nullOr types.int;
                default = null;
              };

              mediaId = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              season = mkOption {
                type = types.nullOr types.int;
                default = null;
                example = 5;
              };

              filter = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              include = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "MWeb";
              };

              exclude = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              quality = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "WEBDL";
              };

              resolution = mkOption {
                type = types.nullOr types.str;
                default = null;
                example = "4K";
              };

              effect = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              totalEpisode = mkOption {
                type = types.nullOr types.int;
                default = null;
              };

              startEpisode = mkOption {
                type = types.nullOr types.int;
                default = null;
                example = 185;
              };

              sites = mkOption {
                type = types.listOf types.str;
                default = [ ];
                description = "站点 domain 列表，模块会在写入前解析成 MoviePilot 的站点 ID。";
                example = [ "m-team.cc" ];
              };

              downloader = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              bestVersion = mkOption {
                type = types.bool;
                default = false;
              };

              savePath = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              searchImdbId = mkOption {
                type = types.bool;
                default = false;
              };

              customWords = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              mediaCategory = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              filterGroups = mkOption {
                type = types.listOf types.str;
                default = [ ];
              };

              episodeGroup = mkOption {
                type = types.nullOr types.str;
                default = null;
              };

              state = mkOption {
                type = types.enum [
                  "N"
                  "R"
                  "P"
                  "S"
                ];
                default = "R";
              };

              username = mkOption {
                type = types.str;
                default = "admin";
              };
            };
          }
        )
      );
      default = null;
      example = literalExpression ''
        [
          {
            name = "斗破苍穹";
            year = "2017";
            type = "电视剧";
            tmdbid = 79481;
            season = 5;
            keyword = "Fights Break Sphere S05";
            include = "MWeb";
            quality = "WEB-DL";
            resolution = "2160p|4K|x2160";
            startEpisode = 185;
            sites = [ "m-team.cc" ];
          }
        ]
      '';
    };

    indexerSites = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = [ "m-team.io" "pthome.net" ];
    };

    rssSites = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = [ "m-team.io" ];
    };

    installedPlugins = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = [ "EnrichWebhook" ];
    };

    pluginConfigs = mkOption {
      type = types.nullOr (types.attrsOf (types.attrsOf jsonValueType));
      default = null;
      example = literalExpression ''
        {
          EnrichWebhook = {
            enabled = true;
            fromEnvironment = {
              webhook = "ENRICH_WEBHOOK_URL";
            };
          };
        }
      '';
    };

    pluginFolders = mkOption {
      type = types.nullOr (
        types.attrsOf (
          types.oneOf [
            (types.listOf types.str)
            (types.submodule {
              options = {
                plugins = mkOption {
                  type = types.listOf types.str;
                  default = [ ];
                };

                order = mkOption {
                  type = types.nullOr types.int;
                  default = null;
                };

                icon = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                };
              };
            })
          ]
        )
      );
      default = null;
      example = literalExpression ''
        {
          Utilities = {
            plugins = [ "EnrichWebhook" ];
            order = 1;
            icon = "Menu";
          };
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
        assertion = cfg.sandboxRoot == null || lib.hasPrefix "/" cfg.sandboxRoot;
        message = "services.moviepilot.sandboxRoot 必须是绝对路径";
      }
      {
        assertion = lib.all (directory: lib.hasPrefix "/" directory.path) cfg.managedDirectories;
        message = "services.moviepilot.managedDirectories[*].path 必须是绝对路径";
      }
      {
        assertion = !sandboxRootInStore;
        message = "services.moviepilot.sandboxRoot 不能位于 /nix/store；该路径只读，无法作为后端可写目录";
      }
      {
        assertion = backendPathsOutsideSandboxRoot == [ ];
        message =
          "services.moviepilot.sandboxRoot 必须覆盖所有整理目录路径，超出范围的路径: "
          + lib.concatStringsSep ", " backendPathsOutsideSandboxRoot;
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
        assertion = !apiSeedConfigured || apiSeedTokenConfigured;
        message =
          "services.moviepilot 声明式配置通过 API 注入时需要提供 API_TOKEN，"
          + "请设置 services.moviepilot.settings.API_TOKEN 或 services.moviepilot.environmentFile。";
      }
    ];

    warnings =
      optional (cfg.user == "root" || cfg.group == "root")
        "services.moviepilot 最好不要以 root 用户或 root 组运行。"
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
    ] ++ managedDirectoryTmpfilesRules;

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
          rsync -ac --delete \
            --exclude 'app/plugins/' \
            --exclude '__pycache__/' \
            --exclude '*.pyc' \
            "$backend_source_dir/" "$backend_dir/"

          find "$backend_dir" -type d -name '__pycache__' -prune -exec rm -rf {} +
          find "$backend_dir" -type f -name '*.pyc' -delete

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

          rsync -ac "$plugins_source_dir/" "$plugins_dir/"
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

          rsync -ac "$resources_source_dir/" "$resources_dir/"
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

    systemd.services.moviepilot-seed-superuser-password = mkIf superuserPasswordSeedConfigured (
      mkSeedApiService {
        description = "Sync MoviePilot superuser password";
        mode = "superuser-password";
        payload = { };
      }
    );

    systemd.services.moviepilot-seed-downloaders = mkIf downloadersConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot downloaders";
        mode = "downloaders";
        payload = serializedDownloaders;
      }
    );

    systemd.services.moviepilot-seed-directories = mkIf directoriesConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot directories";
        mode = "directories";
        payload = serializedDirectories;
      }
    );

    systemd.services.moviepilot-seed-media-servers = mkIf mediaServersConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot media servers";
        mode = "media-servers";
        payload = serializedMediaServers;
      }
    );

    systemd.services.moviepilot-seed-storages = mkIf storagesConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot storages";
        mode = "storages";
        payload = serializedStorages;
      }
    );

    systemd.services.moviepilot-seed-installed-plugins = mkIf installedPluginsConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot installed plugin selection";
        mode = "installed-plugins";
        payload = serializedInstalledPlugins;
      }
    );

    systemd.services.moviepilot-seed-plugin-configs = mkIf pluginConfigsConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot plugin configs";
        mode = "plugin-configs";
        payload = serializedPluginConfigs;
        requires = optionals installedPluginsConfigured [ "moviepilot-seed-installed-plugins.service" ];
        after = optionals installedPluginsConfigured [ "moviepilot-seed-installed-plugins.service" ];
        environment = {
          MOVIEPILOT_MANAGED_PLUGIN_CONFIGS_FILE = "${cfg.stateDir}/config/.managed-plugin-configs.json";
        };
      }
    );

    systemd.services.moviepilot-seed-plugin-folders = mkIf pluginFoldersConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot plugin folders";
        mode = "plugin-folders";
        payload = serializedPluginFolders;
        requires = optionals installedPluginsConfigured [ "moviepilot-seed-installed-plugins.service" ];
        after = optionals installedPluginsConfigured [ "moviepilot-seed-installed-plugins.service" ];
      }
    );

    systemd.services.moviepilot-seed-site-auth = mkIf siteAuthConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot site auth config";
        mode = "site-auth";
        payload = serializedSiteAuth;
      }
    );

    systemd.services.moviepilot-seed-sites = mkIf sitesConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot sites";
        mode = "sites";
        payload = serializedSites;
        requires = optionals siteAuthConfigured [ "moviepilot-seed-site-auth.service" ];
        after = optionals siteAuthConfigured [ "moviepilot-seed-site-auth.service" ];
      }
    );

    systemd.services.moviepilot-seed-indexer-sites = mkIf indexerSitesConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot indexer site selection";
        mode = "indexer-sites";
        payload = serializedIndexerSites;
        requires = optionals sitesConfigured [ "moviepilot-seed-sites.service" ];
        after = optionals sitesConfigured [ "moviepilot-seed-sites.service" ];
      }
    );

    systemd.services.moviepilot-seed-rss-sites = mkIf rssSitesConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot RSS site selection";
        mode = "rss-sites";
        payload = serializedRssSites;
        requires = optionals sitesConfigured [ "moviepilot-seed-sites.service" ];
        after = optionals sitesConfigured [ "moviepilot-seed-sites.service" ];
      }
    );

    systemd.services.moviepilot-seed-subscriptions = mkIf subscriptionsConfigured (
      mkSeedApiService {
        description = "Seed MoviePilot subscriptions";
        mode = "subscriptions";
        payload = serializedSubscriptions;
        requires =
          optionals sitesConfigured [ "moviepilot-seed-sites.service" ]
          ++ optionals indexerSitesConfigured [ "moviepilot-seed-indexer-sites.service" ]
          ++ optionals rssSitesConfigured [ "moviepilot-seed-rss-sites.service" ];
        after =
          optionals sitesConfigured [ "moviepilot-seed-sites.service" ]
          ++ optionals indexerSitesConfigured [ "moviepilot-seed-indexer-sites.service" ]
          ++ optionals rssSitesConfigured [ "moviepilot-seed-rss-sites.service" ];
        environment = {
          MOVIEPILOT_MANAGED_SUBSCRIPTIONS_FILE = "${cfg.stateDir}/config/.managed-subscriptions.json";
        };
      }
    );

    systemd.services.moviepilot-backend = {
      description = "MoviePilot backend";
      wantedBy = [ "multi-user.target" ];
      requires = [ "moviepilot-prepare.service" ];
      after = [ "moviepilot-prepare.service" ];
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
      ] ++ frontendSeedServiceUnits;
      after = [
        "moviepilot-prepare.service"
        "moviepilot-backend.service"
      ] ++ frontendSeedServiceUnits;
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
