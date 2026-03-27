{
  description = "MoviePilotNix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgsPython.url = "github:NixOS/nixpkgs/nixos-unstable";

    moviepilotSrc = {
      url = "github:jxxghp/MoviePilot/v2";
      flake = false;
    };

    moviepilotFrontendSrc = {
      url = "github:jxxghp/MoviePilot-Frontend/v2";
      flake = false;
    };

    moviepilotPluginsSrc = {
      url = "github:jxxghp/MoviePilot-Plugins";
      flake = false;
    };

    moviepilotResourcesSrc = {
      url = "github:jxxghp/MoviePilot-Resources";
      flake = false;
    };
  };

  outputs = inputs@{
    self,
    nixpkgs,
    nixpkgsPython,
    moviepilotSrc,
    moviepilotFrontendSrc,
    moviepilotPluginsSrc,
    moviepilotResourcesSrc,
    ...
  }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);
      sourcePins = import ./nix/sources.nix;
      frontendManifest = builtins.fromJSON (builtins.readFile (moviepilotFrontendSrc + "/package.json"));
      version = frontendManifest.version;
      shortInputRev = input:
        if input ? rev then
          builtins.substring 0 8 input.rev
        else
          "unknown";
      sourceRevisions = {
        backend = moviepilotSrc.rev or null;
        frontend = moviepilotFrontendSrc.rev or null;
        plugins = moviepilotPluginsSrc.rev or null;
        resources = moviepilotResourcesSrc.rev or null;
      };
      packageVersions = {
        backend = "${version}-${shortInputRev moviepilotSrc}";
        frontend = "${version}-${shortInputRev moviepilotFrontendSrc}";
        plugins = "${version}-${shortInputRev moviepilotPluginsSrc}";
        resources = "${version}-${shortInputRev moviepilotResourcesSrc}";
        runtime =
          "${version}-b${shortInputRev moviepilotSrc}-f${shortInputRev moviepilotFrontendSrc}-p${shortInputRev moviepilotPluginsSrc}-r${shortInputRev moviepilotResourcesSrc}";
      };
      module = import ./module.nix { inherit self; };
      resolvePlaywrightBrowsersPath = import ./nix/playwright-browsers-path.nix;
    in
    {
      lib = {
        inherit version;
        inherit packageVersions sourceRevisions;
        sources = {
          backend = builtins.toString moviepilotSrc;
          frontend = builtins.toString moviepilotFrontendSrc;
          plugins = builtins.toString moviepilotPluginsSrc;
          resources = builtins.toString moviepilotResourcesSrc;
        };
      };

      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          pkgsPython = import nixpkgsPython { inherit system; };
          pythonPackages = import ./nix/python-packages.nix { pkgs = pkgsPython; };
          moviepilot-python = pkgsPython.python312.withPackages (_:
            let
              ps = pythonPackages;
            in
            [
              ps.aiofiles
              ps.aiopathlib
              ps.aioshutil
              ps.aiosqlite
              ps.aioquic
              ps.alembic
              ps.anitopy
              ps.apprise
              ps.apscheduler
              ps.asyncpg
              ps.asynctempfile
              ps.bcrypt
              ps.beautifulsoup4
              ps.cacheout
              ps.cachetools
              ps.chardet
              ps.click
              ps.cn2an
              ps.cryptography
              ps.ddgs
              ps.dateparser
              ps."discordpy"
              ps.dnspython
              ps.docker
              ps.feedparser
              ps."fast-bencode"
              ps.fastapi
              ps."faster-whisper"
              ps."func-timeout"
              ps.gotify
              ps.httpx
              ps.iso639
              ps.jieba
              ps.jinja2
              ps.jsonpatch
              ps.langchain
              ps."langchain-community"
              ps."langchain-core"
              ps."langchain-deepseek"
              ps."langchain-google-genai"
              ps."langchain-openai"
              ps.langdetect
              ps.langgraph
              ps.lxml
              ps.mistletoe
              ps.openai
              ps.oss2
              ps.packaging
              ps.parse
              ps.passlib
              ps."paho-mqtt"
              ps.plexapi
              ps."pillow-avif-plugin"
              ps.pillow
              ps.pinyin2hanzi
              ps.proces
              ps.psutil
              ps.psycopg2
              ps."pydantic-settings"
              ps.pydantic
              ps.pymediainfo
              ps.pympler
              ps.pyotp
              ps.pyparsing
              ps.pyquery
              ps.pystray
              ps."pytelegrambotapi"
              ps.pyvirtualdisplay
              ps.pywebpush
              ps.pyyaml
              ps.pytz
              ps."qbittorrent-api"
              ps.redis
              ps.regex
              ps.requests
              ps."requests-cache"
              ps.rsa
              ps."ruamel-yaml"
              ps."sentry-sdk"
              ps.setproctitle
              ps.setuptools
              ps.simpleeval
              ps."slack-bolt"
              ps."slack-sdk"
              ps.smbprotocol
              ps.socksio
              ps.spacy
              ps.srt
              ps.sqlalchemy
              ps."sse-starlette"
              ps.starlette
              ps."telegramify-markdown"
              ps.torrentool
              ps.tqdm
              ps."transmission-rpc"
              ps."python-dateutil"
              ps."python-dotenv"
              ps."python-hosts"
              ps."python-multipart"
              ps.pysocks
              ps.pysubs2
              ps.pyjwt
              ps.pycryptodome
              ps.pypushdeer
              ps."webauthn"
              ps.watchdog
              ps.watchfiles
              ps.websockets
              ps."websocket-client"
              ps.zhconv
              ps."cf-clearance"
              ps.playwright
              ps.uvicorn
            ]);
          moviepilot-playwright-driver = pkgsPython.playwright-driver;
          moviepilot-frontend = pkgs.callPackage ./nix/frontend.nix {
            version = packageVersions.frontend;
            src = moviepilotFrontendSrc;
            iconsSrc = moviepilotPluginsSrc;
            yarnHash = sourcePins.frontendYarnHash;
          };
          moviepilot-backend = pkgs.callPackage ./nix/backend.nix {
            version = packageVersions.backend;
            backendSrc = moviepilotSrc;
          };
          moviepilot-plugins = pkgs.callPackage ./nix/plugins.nix {
            version = packageVersions.plugins;
            backendSrc = moviepilotSrc;
            pluginsSrc = moviepilotPluginsSrc;
          };
          moviepilot-resources = pkgs.callPackage ./nix/resources.nix {
            version = packageVersions.resources;
            resourcesSrc = moviepilotResourcesSrc;
          };
          moviepilot-runtime = pkgs.callPackage ./nix/runtime.nix {
            version = packageVersions.runtime;
            backendPackage = moviepilot-backend;
            pluginsPackage = moviepilot-plugins;
            resourcesPackage = moviepilot-resources;
            frontendPackage = moviepilot-frontend;
          };
          update-upstream = pkgs.writeShellApplication {
            name = "update-upstream";
            runtimeInputs = [
              pkgs.git
              pkgs.gnused
              pkgs.jq
              pkgs.nix
              pkgs.prefetch-yarn-deps
            ];
            text = builtins.readFile ./scripts/update-upstream.sh;
          };
        in
        {
          default = moviepilot-runtime;
          inherit
            moviepilot-python
            moviepilot-playwright-driver
            moviepilot-frontend
            moviepilot-backend
            moviepilot-plugins
            moviepilot-resources
            moviepilot-runtime
            update-upstream
            ;
        });

      apps = forAllSystems (system: {
        update-upstream = {
          type = "app";
          program = "${self.packages.${system}.update-upstream}/bin/update-upstream";
          meta.description = "Update pinned MoviePilot upstream sources and run validation checks";
        };
      });

      nixosModules.default = module;
      nixosModules.moviepilot = module;

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          packages = self.packages.${system};
          backendOutPath = builtins.unsafeDiscardStringContext (builtins.toString packages.moviepilot-backend);
          frontendOutPath = builtins.unsafeDiscardStringContext (builtins.toString packages.moviepilot-frontend);
          pluginsOutPath = builtins.unsafeDiscardStringContext (builtins.toString packages.moviepilot-plugins);
          resourcesOutPath = builtins.unsafeDiscardStringContext (builtins.toString packages.moviepilot-resources);
          defaultPlaywrightBrowsersOutPath =
            builtins.unsafeDiscardStringContext (
              builtins.toString (resolvePlaywrightBrowsersPath packages.moviepilot-playwright-driver)
            );
          pluginsManifestOutPath = "${pluginsOutPath}/share/moviepilot/plugins-manifest";
          resourcesManifestOutPath = "${resourcesOutPath}/share/moviepilot/resources-manifest";
          stateDir = eval.config.services.moviepilot.stateDir;
          exampleFlake = import ./examples/flake.nix;
          exampleEval =
            (exampleFlake.outputs {
              inherit nixpkgs;
              moviepilotNix = self;
            }).nixosConfigurations.nas;
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
          evalNoFrontend = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  frontend.enable = false;
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalExplicitPlaywrightBrowsersPath = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  playwrightBrowsersPath = "/run/moviepilot-playwright-browsers";
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalDownloaders = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  environmentFile = "/run/secrets/moviepilot.env";
                  downloaders = [
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
                          source = "/downloads";
                          target = "/downloads";
                        }
                      ];
                    }
                  ];
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalOpenFirewall = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  openFirewall = true;
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalOpenFirewallNoFrontend = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  openFirewall = true;
                  frontend.enable = false;
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          relativeStateDirEval = builtins.tryEval (
            let
              relative = lib.nixosSystem {
                inherit system;
                modules = [
                  module
                  ({ ... }: {
                    services.moviepilot = {
                      enable = true;
                      stateDir = "moviepilot";
                    };
                    system.stateVersion = "25.05";
                  })
                ];
              };
            in
            relative.config.system.build.toplevel.drvPath
          );
          relativeEnvironmentFileEval = builtins.tryEval (
            let
              relative = lib.nixosSystem {
                inherit system;
                modules = [
                  module
                  ({ ... }: {
                    services.moviepilot = {
                      enable = true;
                      environmentFile = "moviepilot.env";
                    };
                    system.stateVersion = "25.05";
                  })
                ];
              };
            in
            relative.config.system.build.toplevel.drvPath
          );
          playwrightRelativePathEval = builtins.tryEval (
            let
              relative = lib.nixosSystem {
                inherit system;
                modules = [
                  module
                  ({ ... }: {
                    services.moviepilot = {
                      enable = true;
                      playwrightBrowsersPath = "moviepilot-playwright-browsers";
                    };
                    system.stateVersion = "25.05";
                  })
                ];
              };
            in
            relative.config.system.build.toplevel.drvPath
          );
          evalHomeStateDir = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  stateDir = "/home/moviepilot";
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          stateDirReadonlyEval = builtins.tryEval (
            let
              readonly = lib.nixosSystem {
                inherit system;
                modules = [
                  module
                  ({ ... }: {
                    services.moviepilot = {
                      enable = true;
                      stateDir = "/nix/store/moviepilot";
                    };
                    system.stateVersion = "25.05";
                  })
                ];
              };
            in
            readonly.config.system.build.toplevel.drvPath
          );
          reservedSettingEval = builtins.tryEval (
            let
              conflict = lib.nixosSystem {
                inherit system;
                modules = [
                  module
                  ({ ... }: {
                    services.moviepilot = {
                      enable = true;
                      settings.PORT = "3999";
                    };
                    system.stateVersion = "25.05";
                  })
                ];
              };
            in
            conflict.config.system.build.toplevel.drvPath
          );
          evalHardwareWhitelist = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  backend.allowedDevices = [
                    "/dev/dri/renderD128"
                    "/dev/dri/card0"
                  ];
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalHardwareWhitelistWithGroups = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  backend.allowedDevices = [
                    "/dev/dri/renderD128"
                    "/dev/video0"
                  ];
                  backend.supplementaryGroups = [
                    "render"
                    "video"
                  ];
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalHardwareWhitelistWithModes = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  backend.allowedDevices = [
                    {
                      path = "/dev/dri/renderD128";
                      permissions = "r";
                    }
                    {
                      path = "/dev/video0";
                      permissions = "rwm";
                    }
                  ];
                  backend.supplementaryGroups = [
                    "render"
                    "video"
                  ];
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalHardwareWhitelistDuplicate = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  backend.allowedDevices = [
                    "/dev/dri/renderD128"
                    {
                      path = "/dev/dri/renderD128";
                      permissions = "rw";
                    }
                  ];
                  backend.supplementaryGroups = [ "render" ];
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          evalHardwareWhitelistConflict = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  backend.allowedDevices = [
                    {
                      path = "/dev/video0";
                      permissions = "r";
                    }
                    {
                      path = "/dev/video0";
                      permissions = "rwm";
                    }
                  ];
                  backend.supplementaryGroups = [ "video" ];
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          invalidDevicePathEval = builtins.tryEval (
            let
              invalid = lib.nixosSystem {
                inherit system;
                modules = [
                  module
                  ({ ... }: {
                    services.moviepilot = {
                      enable = true;
                      backend.allowedDevices = [ "/proc/kmsg" ];
                    };
                    system.stateVersion = "25.05";
                  })
                ];
              };
            in
            invalid.config.system.build.toplevel.drvPath
          );
          evalEnvironmentFileInStore = lib.nixosSystem {
            inherit system;
            modules = [
              module
              ({ ... }: {
                services.moviepilot = {
                  enable = true;
                  environmentFile = "/nix/store/fake-moviepilot.env";
                };
                system.stateVersion = "25.05";
              })
            ];
          };
          portConflictEval = builtins.tryEval (
            let
              conflict = lib.nixosSystem {
                inherit system;
                modules = [
                  module
                  ({ ... }: {
                    services.moviepilot = {
                      enable = true;
                      backend.port = 3000;
                      frontend.port = 3000;
                    };
                    system.stateVersion = "25.05";
                  })
                ];
              };
            in
            conflict.config.system.build.toplevel.drvPath
          );
        in
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.ReadWritePaths == [
          "${stateDir}/config"
          "${stateDir}/runtime"
        ];
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.PrivateIPC == true;
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.PrivateDevices == true;
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.KeyringMode == "private";
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.MemoryDenyWriteExecute == true;
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.ProcSubset == "pid";
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.ProtectHome == true;
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.ProtectProc == "invisible";
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.RemoveIPC == true;
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.SystemCallErrorNumber == "EPERM";
        assert eval.config.systemd.services.moviepilot-prepare.serviceConfig.SystemCallFilter == [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.ReadWritePaths == [ "${stateDir}/config" ];
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.PrivateIPC == true;
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.PrivateDevices == true;
        assert lib.hasInfix "/bin/python -m app.main" eval.config.systemd.services.moviepilot-backend.serviceConfig.ExecStart;
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.KeyringMode == "private";
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.ProcSubset == "all";
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.ProtectHome == true;
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.ProtectProc == "invisible";
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.RemoveIPC == true;
        assert eval.config.systemd.services.moviepilot-backend.serviceConfig.RestrictAddressFamilies == [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        assert eval.config.systemd.services.moviepilot-backend.environment.HOST == "127.0.0.1";
        assert eval.config.systemd.services.moviepilot-backend.environment.PLAYWRIGHT_BROWSERS_PATH == defaultPlaywrightBrowsersOutPath;
        assert eval.config.systemd.services.moviepilot-backend.environment.NGINX_PORT == "3000";
        assert evalNoFrontend.config.systemd.services.moviepilot-backend.environment.HOST == "0.0.0.0";
        assert evalExplicitPlaywrightBrowsersPath.config.systemd.services.moviepilot-backend.environment.PLAYWRIGHT_BROWSERS_PATH == "/run/moviepilot-playwright-browsers";
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-seed-downloaders" ] eval.config);
        assert lib.hasAttrByPath [ "systemd" "services" "moviepilot-seed-downloaders" ] evalDownloaders.config;
        assert evalDownloaders.config.systemd.services.moviepilot-seed-downloaders.serviceConfig.EnvironmentFile == "/run/secrets/moviepilot.env";
        assert lib.hasInfix "moviepilot-seed-downloaders.service" (builtins.concatStringsSep " " evalDownloaders.config.systemd.services.moviepilot-backend.requires);
        assert lib.hasInfix "qbittorrent" evalDownloaders.config.systemd.services.moviepilot-seed-downloaders.script;
        assert lib.hasInfix "QBITTORRENT_PASSWORD" evalDownloaders.config.systemd.services.moviepilot-seed-downloaders.script;
        assert evalOpenFirewall.config.networking.firewall.allowedTCPPorts == [ 3000 ];
        assert evalOpenFirewallNoFrontend.config.networking.firewall.allowedTCPPorts == [ 3001 ];
        assert relativeStateDirEval.success == false;
        assert relativeEnvironmentFileEval.success == false;
        assert playwrightRelativePathEval.success == false;
        assert lib.hasInfix "${stateDir}/config/plugins" eval.config.systemd.services.moviepilot-prepare.script;
        assert lib.hasInfix backendOutPath eval.config.systemd.services.moviepilot-prepare.script;
        assert lib.hasInfix pluginsOutPath eval.config.systemd.services.moviepilot-prepare.script;
        assert lib.hasInfix resourcesOutPath eval.config.systemd.services.moviepilot-prepare.script;
        assert lib.hasInfix pluginsManifestOutPath eval.config.systemd.services.moviepilot-prepare.script;
        assert lib.hasInfix resourcesManifestOutPath eval.config.systemd.services.moviepilot-prepare.script;
        assert exampleEval.pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        assert exampleEval.config.services.moviepilot.enable == true;
        assert exampleEval.config.services.moviepilot.stateDir == "/var/lib/moviepilot";
        assert exampleEval.config.services.moviepilot.environmentFile == "/run/secrets/moviepilot.env";
        assert exampleEval.config.services.moviepilot.settings.SUPERUSER == "admin";
        assert builtins.any (
          rule: rule == "z ${stateDir} 0750 moviepilot moviepilot -"
        ) eval.config.systemd.tmpfiles.rules;
        assert builtins.any (
          rule: rule == "Z ${stateDir}/config 0750 moviepilot moviepilot -"
        ) eval.config.systemd.tmpfiles.rules;
        assert builtins.any (
          rule: rule == "Z ${stateDir}/runtime 0750 moviepilot moviepilot -"
        ) eval.config.systemd.tmpfiles.rules;
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-prepare" "serviceConfig" "EnvironmentFile" ] eval.config);
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-frontend" "serviceConfig" "ReadWritePaths" ] eval.config);
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-frontend" "serviceConfig" "EnvironmentFile" ] eval.config);
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.PrivateIPC == true;
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.PrivateDevices == true;
        assert lib.hasInfix "/bin/node service.js" eval.config.systemd.services.moviepilot-frontend.serviceConfig.ExecStart;
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.KeyringMode == "private";
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.ProcSubset == "pid";
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.ProtectHome == true;
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.ProtectProc == "invisible";
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.RemoveIPC == true;
        assert eval.config.systemd.services.moviepilot-frontend.serviceConfig.RestrictAddressFamilies == [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        assert eval.config.systemd.services.moviepilot-frontend.environment.PORT == "3001";
        assert eval.config.systemd.services.moviepilot-frontend.environment.NGINX_PORT == "3000";
        assert !(lib.hasAttr "CONFIG_DIR" eval.config.systemd.services.moviepilot-frontend.environment);
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-frontend" ] evalNoFrontend.config);
        assert !(lib.hasInfix frontendOutPath evalNoFrontend.config.systemd.services.moviepilot-prepare.script);
        assert evalNoFrontend.config.systemd.services.moviepilot-backend.environment.NGINX_PORT == "3001";
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-prepare" "serviceConfig" "ProtectHome" ] evalHomeStateDir.config);
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-backend" "serviceConfig" "ProtectHome" ] evalHomeStateDir.config);
        assert !(lib.hasAttrByPath [ "systemd" "services" "moviepilot-frontend" "serviceConfig" "ProtectHome" ] evalHomeStateDir.config);
        assert stateDirReadonlyEval.success == false;
        assert reservedSettingEval.success == false;
        assert builtins.any (
          msg: lib.hasInfix "ProtectHome" msg
        ) evalHomeStateDir.config.warnings;
        assert evalHardwareWhitelist.config.systemd.services.moviepilot-backend.serviceConfig.PrivateDevices == false;
        assert evalHardwareWhitelist.config.systemd.services.moviepilot-backend.serviceConfig.DevicePolicy == "closed";
        assert evalHardwareWhitelist.config.systemd.services.moviepilot-backend.serviceConfig.DeviceAllow == [
          "/dev/dri/renderD128 rw"
          "/dev/dri/card0 rw"
        ];
        assert builtins.any (
          msg: lib.hasInfix "supplementaryGroups" msg && lib.hasInfix "render" msg
        ) evalHardwareWhitelist.config.warnings;
        assert evalHardwareWhitelistWithGroups.config.systemd.services.moviepilot-backend.serviceConfig.SupplementaryGroups == [
          "render"
          "video"
        ];
        assert !(builtins.any (
          msg: lib.hasInfix "supplementaryGroups" msg
        ) evalHardwareWhitelistWithGroups.config.warnings);
        assert evalHardwareWhitelistWithModes.config.systemd.services.moviepilot-backend.serviceConfig.DeviceAllow == [
          "/dev/dri/renderD128 r"
          "/dev/video0 rwm"
        ];
        assert evalHardwareWhitelistWithModes.config.systemd.services.moviepilot-backend.serviceConfig.SupplementaryGroups == [
          "render"
          "video"
        ];
        assert evalHardwareWhitelistDuplicate.config.systemd.services.moviepilot-backend.serviceConfig.DeviceAllow == [
          "/dev/dri/renderD128 rw"
        ];
        assert builtins.any (
          msg: lib.hasInfix "重复设备路径" msg && lib.hasInfix "/dev/dri/renderD128" msg
        ) evalHardwareWhitelistDuplicate.config.warnings;
        assert evalHardwareWhitelistConflict.config.systemd.services.moviepilot-backend.serviceConfig.DeviceAllow == [
          "/dev/video0 rwm"
        ];
        assert builtins.any (
          msg: lib.hasInfix "不同 permissions" msg && lib.hasInfix "/dev/video0 -> rwm" msg
        ) evalHardwareWhitelistConflict.config.warnings;
        assert invalidDevicePathEval.success == false;
        assert builtins.any (
          msg: lib.hasInfix "environmentFile" msg && lib.hasInfix "/nix/store" msg
        ) evalEnvironmentFileInStore.config.warnings;
        assert portConflictEval.success == false;
        {
          example-eval = pkgs.runCommand "moviepilot-example-eval" { } ''
            echo ${lib.escapeShellArg exampleEval.config.services.moviepilot.stateDir} >/dev/null
            echo ${lib.escapeShellArg exampleEval.config.services.moviepilot.environmentFile} >/dev/null
            touch "$out"
          '';
          module-eval = pkgs.runCommand "moviepilot-module-eval" { } ''
            echo ${lib.escapeShellArg eval.config.systemd.services.moviepilot-backend.description} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-runtime.drvPath} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-python.drvPath} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-frontend.drvPath} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-backend.drvPath} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-plugins.drvPath} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-resources.drvPath} >/dev/null
            test -f ${lib.escapeShellArg "${frontendOutPath}/share/moviepilot/frontend/node_modules/express/package.json"}
            test -f ${lib.escapeShellArg pluginsManifestOutPath}
            test -f ${lib.escapeShellArg resourcesManifestOutPath}
            echo ${lib.escapeShellArg evalNoFrontend.config.systemd.services.moviepilot-prepare.script} >/dev/null
            echo ${lib.escapeShellArg (lib.concatStringsSep "\n" evalHomeStateDir.config.warnings)} >/dev/null
            echo ${lib.escapeShellArg (lib.concatStringsSep "\n" evalHardwareWhitelist.config.warnings)} >/dev/null
            echo ${lib.escapeShellArg (lib.concatStringsSep "\n" evalHardwareWhitelistDuplicate.config.warnings)} >/dev/null
            echo ${lib.escapeShellArg (lib.concatStringsSep "\n" evalHardwareWhitelistConflict.config.warnings)} >/dev/null
            echo ${lib.escapeShellArg (lib.concatStringsSep "\n" evalEnvironmentFileInStore.config.warnings)} >/dev/null
            if ${lib.boolToString relativeStateDirEval.success}; then
              echo "relative stateDir assertion unexpectedly succeeded" >&2
              exit 1
            fi
            if ${lib.boolToString relativeEnvironmentFileEval.success}; then
              echo "relative environmentFile assertion unexpectedly succeeded" >&2
              exit 1
            fi
            if ${lib.boolToString playwrightRelativePathEval.success}; then
              echo "relative playwright path assertion unexpectedly succeeded" >&2
              exit 1
            fi
            if ${lib.boolToString reservedSettingEval.success}; then
              echo "reserved settings assertion unexpectedly succeeded" >&2
              exit 1
            fi
            if ${lib.boolToString invalidDevicePathEval.success}; then
              echo "invalid device path assertion unexpectedly succeeded" >&2
              exit 1
            fi
            touch "$out"
          '';
          update-upstream-script = pkgs.runCommand "moviepilot-update-upstream-script" {
            nativeBuildInputs = [
              pkgs.diffutils
              pkgs.git
              pkgs.gnused
              pkgs.jq
            ];
          } ''
            set -euo pipefail

            init_repo() {
              local repo="$1"

              mkdir -p "$repo/scripts" "$repo/nix"

              printf '%s\n' \
                '{' \
                '  description = "update-upstream test";' \
                '}' \
                > "$repo/flake.nix"

              printf '%s\n' \
                '{' \
                '  "nodes": {' \
                '    "moviepilotSrc": {' \
                '      "locked": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot",' \
                '        "rev": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"' \
                '      },' \
                '      "original": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot",' \
                '        "ref": "v2",' \
                '        "type": "github"' \
                '      }' \
                '    },' \
                '    "moviepilotFrontendSrc": {' \
                '      "locked": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot-Frontend",' \
                '        "rev": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
                '      },' \
                '      "original": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot-Frontend",' \
                '        "ref": "v2",' \
                '        "type": "github"' \
                '      }' \
                '    },' \
                '    "moviepilotPluginsSrc": {' \
                '      "locked": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot-Plugins",' \
                '        "rev": "cccccccccccccccccccccccccccccccccccccccc"' \
                '      },' \
                '      "original": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot-Plugins",' \
                '        "type": "github"' \
                '      }' \
                '    },' \
                '    "moviepilotResourcesSrc": {' \
                '      "locked": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot-Resources",' \
                '        "rev": "dddddddddddddddddddddddddddddddddddddddd"' \
                '      },' \
                '      "original": {' \
                '        "owner": "jxxghp",' \
                '        "repo": "MoviePilot-Resources",' \
                '        "type": "github"' \
                '      }' \
                '    }' \
                '  },' \
                '  "root": ""' \
                '}' \
                > "$repo/flake.lock"

              printf '%s\n' \
                '{' \
                '  frontendYarnHash = "sha256-old-test-hash";' \
                '}' \
                > "$repo/nix/sources.nix"

              cp ${./scripts/update-upstream.sh} "$repo/scripts/update-upstream.sh"
              chmod +x "$repo/scripts/update-upstream.sh"

              (
                cd "$repo"
                git init -q
                git config user.name "Codex Check"
                git config user.email "codex@example.invalid"
                git add flake.nix flake.lock nix/sources.nix scripts/update-upstream.sh
                git commit -qm init
              )
            }

            repo_dirty="$TMPDIR/repo-dirty"
            init_repo "$repo_dirty"

            (
              cd "$repo_dirty"
              ${packages.update-upstream}/bin/update-upstream --help | grep -F -- '--allow-dirty' >/dev/null

              touch README.md

              if ${packages.update-upstream}/bin/update-upstream --skip-check > "$TMPDIR/update-upstream-dirty.out" 2>&1; then
                echo "dirty guard failed" >&2
                exit 1
              fi

              grep -F "未提交改动" "$TMPDIR/update-upstream-dirty.out" >/dev/null
            )

            repo_quick="$TMPDIR/repo-quick"
            quick_log_dir="$TMPDIR/quick-log"
            init_repo "$repo_quick"
            mkdir -p "$repo_quick/fakebin" "$quick_log_dir/upstream-frontend"

            printf '%s\n' \
              '{ "version": "2.9.19" }' \
              > "$quick_log_dir/upstream-frontend/package.json"

            printf '%s\n' \
              '#!${pkgs.bash}/bin/bash' \
              'set -euo pipefail' \
              "" \
              'log_dir="''${UPDATE_UPSTREAM_TEST_LOG_DIR:?}"' \
              "" \
              'case "$1" in' \
              '  flake)' \
              '    case "$2" in' \
              '      prefetch)' \
              '        shift 2' \
              '        if [[ "$1" == "--json" && "$2" == "--refresh" ]]; then' \
              '          printf "{\"storePath\":\"%s/upstream-frontend\"}\n" "$log_dir"' \
              '        else' \
              '          echo "unexpected nix flake prefetch args: $*" >&2' \
              '          exit 1' \
              '        fi' \
              '        ;;' \
              '      update)' \
              '        shift 2' \
              '        printf "%s\n" "$@" > "$log_dir/update-args"' \
              '        touch "$log_dir/version-bumped"' \
              '        ;;' \
              '      *)' \
              '        echo "unexpected nix flake subcommand: $2" >&2' \
              '        exit 1' \
              '        ;;' \
              '    esac' \
              '    ;;' \
              '  eval)' \
              '    shift' \
              '    if [[ "$1" == "--impure" && "$2" == "--raw" && "$3" == "--expr" && "$4" == "builtins.currentSystem" ]]; then' \
              '      printf "x86_64-linux\n"' \
              '    elif [[ "$1" == "--raw" && "$2" == ".#lib.version" ]]; then' \
              '      if [[ -e "$log_dir/version-bumped" ]]; then' \
              '        printf "2.9.19\n"' \
              '      else' \
              '        printf "2.9.18\n"' \
              '      fi' \
              '    else' \
              '      echo "unexpected nix eval args: $*" >&2' \
              '      exit 1' \
              '    fi' \
              '    ;;' \
              '  build)' \
              '    shift' \
              '    target="$1"' \
              '    shift' \
              '    if [[ "$#" -ne 1 || "$1" != "--no-link" ]]; then' \
              '      echo "unexpected nix build args" >&2' \
              '      exit 1' \
              '    fi' \
              '    if [[ "$target" == .#checks.* ]]; then' \
              '      printf "%s\n" "$target" >> "$log_dir/check-targets"' \
              '    else' \
              '      printf "%s\n" "$target" >> "$log_dir/build-targets"' \
              '    fi' \
              '    ;;' \
              '  *)' \
              '    echo "unexpected nix command: $1" >&2' \
              '    exit 1' \
              '    ;;' \
              'esac' \
              > "$repo_quick/fakebin/nix"
            chmod +x "$repo_quick/fakebin/nix"

            (
              cd "$repo_quick"
              touch README.md
              export UPDATE_UPSTREAM_TEST_LOG_DIR="$quick_log_dir"
              export PATH="$repo_quick/fakebin:$PATH"
              bash ./scripts/update-upstream.sh --allow-dirty backend backend plugins > "$TMPDIR/update-upstream-quick.out"

              grep -F "==> 已启用 --allow-dirty" "$TMPDIR/update-upstream-quick.out" >/dev/null
              grep -F "==> 更新上游输入: backend plugins" "$TMPDIR/update-upstream-quick.out" >/dev/null

              printf '%s\n' \
                moviepilotSrc \
                moviepilotPluginsSrc \
                > "$TMPDIR/update-upstream-quick-update-expected"
              cmp "$TMPDIR/update-upstream-quick-update-expected" "$quick_log_dir/update-args"

              printf '%s\n' \
                .#packages.x86_64-linux.moviepilot-runtime \
                .#packages.x86_64-linux.moviepilot-python \
                .#packages.x86_64-linux.moviepilot-backend \
                .#packages.x86_64-linux.moviepilot-plugins \
                .#packages.x86_64-linux.moviepilot-frontend \
                > "$TMPDIR/update-upstream-quick-build-expected"
              cmp "$TMPDIR/update-upstream-quick-build-expected" "$quick_log_dir/build-targets"

              printf '%s\n' \
                .#checks.x86_64-linux.module-eval \
                .#checks.x86_64-linux.example-eval \
                .#checks.x86_64-linux.nixos-test \
                .#checks.x86_64-linux.nixos-test-no-frontend \
                > "$TMPDIR/update-upstream-quick-check-expected"
              cmp "$TMPDIR/update-upstream-quick-check-expected" "$quick_log_dir/check-targets"
            )

            repo_frontend="$TMPDIR/repo-frontend"
            frontend_log_dir="$TMPDIR/frontend-log"
            init_repo "$repo_frontend"
            mkdir -p "$repo_frontend/fakebin" "$frontend_log_dir/frontend-src" "$frontend_log_dir/upstream-frontend"
            touch "$frontend_log_dir/frontend-src/yarn.lock"

            printf '%s\n' \
              '{ "version": "2.9.19" }' \
              > "$frontend_log_dir/upstream-frontend/package.json"

            printf '%s\n' \
              '#!${pkgs.bash}/bin/bash' \
              'set -euo pipefail' \
              "" \
              'log_dir="''${UPDATE_UPSTREAM_TEST_LOG_DIR:?}"' \
              "" \
              'case "$1" in' \
              '  flake)' \
              '    case "$2" in' \
              '      prefetch)' \
              '        shift 2' \
              '        if [[ "$1" == "--json" && "$2" == "--refresh" ]]; then' \
              '          printf "{\"storePath\":\"%s/upstream-frontend\"}\n" "$log_dir"' \
              '        else' \
              '          echo "unexpected nix flake prefetch args: $*" >&2' \
              '          exit 1' \
              '        fi' \
              '        ;;' \
              '      update)' \
              '        shift 2' \
              '        printf "%s\n" "$@" > "$log_dir/update-args"' \
              '        touch "$log_dir/version-bumped"' \
              '        ;;' \
              '      *)' \
              '        echo "unexpected nix flake subcommand: $2" >&2' \
              '        exit 1' \
              '        ;;' \
              '    esac' \
              '    ;;' \
              '  eval)' \
              '    shift' \
              '    if [[ "$1" == "--raw" && "$2" == ".#lib.version" ]]; then' \
              '      if [[ -e "$log_dir/version-bumped" ]]; then' \
              '        printf "2.9.19\n"' \
              '      else' \
              '        printf "2.9.18\n"' \
              '      fi' \
              '    elif [[ "$1" == "--raw" && "$2" == ".#lib.sources.frontend" ]]; then' \
              '      printf "%s/frontend-src\n" "$log_dir"' \
              '    else' \
              '      echo "unexpected nix eval args: $*" >&2' \
              '      exit 1' \
              '    fi' \
              '    ;;' \
              '  hash)' \
              '    shift' \
              '    if [[ "$1" == "convert" && "$2" == "--hash-algo" && "$3" == "sha256" && "$4" == "--to" && "$5" == "sri" ]]; then' \
              '      printf "sha256-new-test-hash\n"' \
              '    else' \
              '      echo "unexpected nix hash args: $*" >&2' \
              '      exit 1' \
              '    fi' \
              '    ;;' \
              '  *)' \
              '    echo "unexpected nix command: $1" >&2' \
              '    exit 1' \
              '    ;;' \
              'esac' \
              > "$repo_frontend/fakebin/nix"
            chmod +x "$repo_frontend/fakebin/nix"

            printf '%s\n' \
              '#!${pkgs.bash}/bin/bash' \
              'set -euo pipefail' \
              'printf "%s\n" "$1" > "''${UPDATE_UPSTREAM_TEST_LOG_DIR:?}/prefetch-arg"' \
              'printf "sha256-raw-test-hash\n"' \
              > "$repo_frontend/fakebin/prefetch-yarn-deps"
            chmod +x "$repo_frontend/fakebin/prefetch-yarn-deps"

            (
              cd "$repo_frontend"
              export UPDATE_UPSTREAM_TEST_LOG_DIR="$frontend_log_dir"
              export PATH="$repo_frontend/fakebin:$PATH"
              bash ./scripts/update-upstream.sh --allow-dirty frontend --skip-check > "$TMPDIR/update-upstream-frontend.out"

              grep -F "frontendYarnHash: sha256-old-test-hash -> sha256-new-test-hash" "$TMPDIR/update-upstream-frontend.out" >/dev/null
              grep -F 'frontendYarnHash = "sha256-new-test-hash";' nix/sources.nix >/dev/null
              grep -F "$frontend_log_dir/frontend-src/yarn.lock" "$frontend_log_dir/prefetch-arg" >/dev/null

              printf '%s\n' \
                moviepilotFrontendSrc \
                > "$TMPDIR/update-upstream-frontend-update-expected"
              cmp "$TMPDIR/update-upstream-frontend-update-expected" "$frontend_log_dir/update-args"
            )

            repo_same_version="$TMPDIR/repo-same-version"
            same_version_log_dir="$TMPDIR/same-version-log"
            init_repo "$repo_same_version"
            mkdir -p "$repo_same_version/fakebin" "$same_version_log_dir/upstream-frontend"

            cp "$repo_same_version/flake.lock" "$TMPDIR/same-version-flake.lock.before"
            cp "$repo_same_version/nix/sources.nix" "$TMPDIR/same-version-sources.nix.before"

            printf '%s\n' \
              '{ "version": "2.9.18" }' \
              > "$same_version_log_dir/upstream-frontend/package.json"

            printf '%s\n' \
              '#!${pkgs.bash}/bin/bash' \
              'set -euo pipefail' \
              "" \
              'log_dir="''${UPDATE_UPSTREAM_TEST_LOG_DIR:?}"' \
              "" \
              'case "$1" in' \
              '  flake)' \
              '    case "$2" in' \
              '      prefetch)' \
              '        shift 2' \
              '        if [[ "$1" == "--json" && "$2" == "--refresh" ]]; then' \
              '          printf "{\"storePath\":\"%s/upstream-frontend\"}\n" "$log_dir"' \
              '        else' \
              '          echo "unexpected nix flake prefetch args: $*" >&2' \
              '          exit 1' \
              '        fi' \
              '        ;;' \
              '      update)' \
              '        shift 2' \
              '        printf "%s\n" "$@" > "$log_dir/update-args"' \
              '        ${pkgs.python3}/bin/python3 -c "import json, sys; path = sys.argv[1]; data = json.load(open(path, \"r\", encoding=\"utf-8\")); data[\"nodes\"][\"moviepilotSrc\"][\"locked\"][\"rev\"] = \"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\"; open(path, \"w\", encoding=\"utf-8\").write(json.dumps(data, indent=2) + \"\\n\")" "$PWD/flake.lock"' \
              '        ;;' \
              '      *)' \
              '        echo "unexpected nix flake subcommand: $2" >&2' \
              '        exit 1' \
              '        ;;' \
              '    esac' \
              '    ;;' \
              '  eval)' \
              '    shift' \
              '    if [[ "$1" == "--raw" && "$2" == ".#lib.version" ]]; then' \
              '      printf "2.9.18\n"' \
              '    else' \
              '      echo "unexpected nix eval args: $*" >&2' \
              '      exit 1' \
              '    fi' \
              '    ;;' \
              '  *)' \
              '    echo "unexpected nix command: $1" >&2' \
              '    exit 1' \
              '    ;;' \
              'esac' \
              > "$repo_same_version/fakebin/nix"
            chmod +x "$repo_same_version/fakebin/nix"

            (
              cd "$repo_same_version"
              export UPDATE_UPSTREAM_TEST_LOG_DIR="$same_version_log_dir"
              export PATH="$repo_same_version/fakebin:$PATH"
              bash ./scripts/update-upstream.sh --allow-dirty backend --skip-check > "$TMPDIR/update-upstream-same-version.out"

              grep -F "==> 当前官方版本: 2.9.18" "$TMPDIR/update-upstream-same-version.out" >/dev/null
              grep -F "==> 上游官方版本: 2.9.18" "$TMPDIR/update-upstream-same-version.out" >/dev/null
              grep -F "==> 官方版本未变化 (2.9.18)，跳过本次同步" "$TMPDIR/update-upstream-same-version.out" >/dev/null

              if [[ -e "$same_version_log_dir/update-args" ]]; then
                echo "flake update should not run when version is unchanged" >&2
                exit 1
              fi

              cmp "$TMPDIR/same-version-flake.lock.before" flake.lock
              cmp "$TMPDIR/same-version-sources.nix.before" nix/sources.nix
            )

            touch "$out"
          '';
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          nixos-test = import ./nix/tests/moviepilot.nix {
            inherit pkgs module;
            exerciseOwnershipRepair = true;
          };
          nixos-test-no-frontend = import ./nix/tests/moviepilot.nix {
            inherit pkgs module;
            frontend = false;
          };
          nixos-test-allowed-devices = import ./nix/tests/moviepilot.nix {
            inherit pkgs module;
            allowedDevices = [ "/dev/full" ];
            backendSupplementaryGroups = [ "moviepilotdevice" ];
            ensureGroups = [ "moviepilotdevice" ];
          };
        });
    };
}
