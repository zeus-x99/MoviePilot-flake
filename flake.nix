{
  description = "MoviePilot-flake";

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
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);
      sourcePins = import ./nix/sources.nix;
      frontendManifest = builtins.fromJSON (builtins.readFile (moviepilotFrontendSrc + "/package.json"));
      version = frontendManifest.version;
      module = import ./module.nix { inherit self; };
    in
    {
      lib = {
        inherit version;
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
            inherit version;
            src = moviepilotFrontendSrc;
            iconsSrc = moviepilotPluginsSrc;
            yarnHash = sourcePins.frontendYarnHash;
          };
          moviepilot-runtime = pkgs.callPackage ./nix/runtime.nix {
            inherit version;
            backendSrc = moviepilotSrc;
            pluginsSrc = moviepilotPluginsSrc;
            resourcesSrc = moviepilotResourcesSrc;
            frontendPackage = moviepilot-frontend;
          };
          update-upstream = pkgs.writeShellApplication {
            name = "update-upstream";
            runtimeInputs = [
              pkgs.git
              pkgs.gnused
              pkgs.nix
              pkgs.prefetch-yarn-deps
            ];
            text = builtins.readFile ./scripts/update-upstream.sh;
          };
        in
        {
          default = moviepilot-runtime;
          inherit moviepilot-python moviepilot-playwright-driver moviepilot-frontend moviepilot-runtime update-upstream;
        });

      apps = forAllSystems (system: {
        update-upstream = {
          type = "app";
          program = "${self.packages.${system}.update-upstream}/bin/update-upstream";
        };
      });

      nixosModules.default = module;
      nixosModules.moviepilot = module;

      checks = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          packages = self.packages.${system};
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
            echo ${lib.escapeShellArg packages.moviepilot-runtime.drvPath} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-python.drvPath} >/dev/null
            echo ${lib.escapeShellArg packages.moviepilot-frontend.drvPath} >/dev/null
            touch "$out"
          '';
        });
    };
}
