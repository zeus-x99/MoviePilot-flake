{ pkgs }:

let
  py = pkgs.python312Packages;
in
py.overrideScope (final: prev:
  let
    disableChecks = pkg: pkg.overridePythonAttrs (_: {
      doCheck = false;
    });

    mkSetuptools = {
      pname,
      version,
      url,
      hash,
      propagatedBuildInputs ? [ ],
      buildInputs ? [ ],
      nativeBuildInputs ? [ ],
      pythonImportsCheck ? [ ],
    }:
      prev.buildPythonPackage {
        inherit pname version propagatedBuildInputs buildInputs nativeBuildInputs pythonImportsCheck;
        src = pkgs.fetchurl {
          inherit url hash;
        };
        format = "setuptools";
        doCheck = false;
      };

    mkPyproject = {
      pname,
      version,
      url,
      hash,
      propagatedBuildInputs ? [ ],
      buildInputs ? [ ],
      nativeBuildInputs ? [ ],
      pythonImportsCheck ? [ ],
      pythonRelaxDeps ? [ ],
    }:
      prev.buildPythonPackage {
        inherit pname version propagatedBuildInputs buildInputs nativeBuildInputs pythonImportsCheck pythonRelaxDeps;
        src = pkgs.fetchurl {
          inherit url hash;
        };
        pyproject = true;
        doCheck = false;
      };
  in
  {
    proces = mkSetuptools {
      pname = "proces";
      version = "0.1.7";
      url = "https://files.pythonhosted.org/packages/2c/3d/4159b57736ced0fd22553226df20a985ef7655519c80ffcb8a9fb49ebeee/proces-0.1.7.tar.gz";
      hash = "sha256-cKBdnpc91oX3qQksWL5pWoGBpBHWN5bCEyMv0/3EN3U=";
      pythonImportsCheck = [ "proces" ];
    };

    cn2an = mkSetuptools {
      pname = "cn2an";
      version = "0.5.23";
      url = "https://files.pythonhosted.org/packages/a3/0b/35c9379122a2b551b22aa47d67b2a268eba2e77bc7509f52ed3f0ce6363e/cn2an-0.5.23.tar.gz";
      hash = "sha256-7aBqY+Xv9KZEiNnyLl8qTOym6qY0FuT3ceZ+3ssaW9s=";
      propagatedBuildInputs = [ final.proces ];
      pythonImportsCheck = [ "cn2an" ];
    };

    zhconv = mkSetuptools {
      pname = "zhconv";
      version = "1.4.3";
      url = "https://files.pythonhosted.org/packages/25/47/c8ae2d5d4025e253211ff3d8c163f457db1da94976cb582337a5ab76cb87/zhconv-1.4.3.tar.gz";
      hash = "sha256-rULZBXygYF+OQdYrZ8p5f4efWBk+5oQFYsUUWbJpjEU=";
      pythonImportsCheck = [ "zhconv" ];
    };

    "telegramify-markdown" = mkPyproject {
      pname = "telegramify_markdown";
      version = "0.5.2";
      url = "https://files.pythonhosted.org/packages/d1/db/9f9bc7f495b7420abea642efa7622f92b17139465e01187db72fc139f79f/telegramify_markdown-0.5.2.tar.gz";
      hash = "sha256-sKeqRbOB/wH8nsGxn46z+XHLUWVCOKcpCHYDUyWgXig=";
      nativeBuildInputs = [
        final."pdm-backend"
        final.pythonRelaxDepsHook
      ];
      propagatedBuildInputs = [ final.mistletoe ];
      pythonRelaxDeps = [ "mistletoe" ];
      pythonImportsCheck = [ "telegramify_markdown" ];
    };

    "cf-clearance" = mkPyproject {
      pname = "cf_clearance";
      version = "0.31.0";
      url = "https://files.pythonhosted.org/packages/22/2d/b6d3b6c9e9b5b14c7576f6990c15f3383bf8bbf929030b60aa81d971f4ef/cf_clearance-0.31.0.tar.gz";
      hash = "sha256-+KtgUFznRQmpd4degxulKqnPjlcS9YQLi51t6c1k0Yk=";
      nativeBuildInputs = [ final."pdm-backend" ];
      propagatedBuildInputs = [ final.playwright ];
      pythonImportsCheck = [ "cf_clearance" ];
    };

    torrentool = mkSetuptools {
      pname = "torrentool";
      version = "1.2.0";
      url = "https://files.pythonhosted.org/packages/f7/67/a2aa492be0207f89952fa766005893e304aaf9971336cd2a8a7a79d3ff9c/torrentool-1.2.0.tar.gz";
      hash = "sha256-cs3QSer4Vt3JB9HWFSd2TvAohRIIfZOkkmfgDEAzxCk=";
      pythonImportsCheck = [ "torrentool" ];
    };

    cacheout = mkPyproject {
      pname = "cacheout";
      version = "0.16.0";
      url = "https://files.pythonhosted.org/packages/d1/60/ed4c4b27b2131a0b2cc461789be2cf06866644ca462cb34a5d8fca114c15/cacheout-0.16.0.tar.gz";
      hash = "sha256-7iZIl8uqCJrl9AbaEZUml9mfp/NYPPq2n+igD/jhlS0=";
      nativeBuildInputs = [
        final.setuptools
        final.wheel
      ];
      pythonImportsCheck = [ "cacheout" ];
    };

    "fast-bencode" = mkPyproject {
      pname = "fast_bencode";
      version = "1.1.8";
      url = "https://files.pythonhosted.org/packages/9b/00/7c053413e06baf507c14c62c9baf0b39a21cd3060a77870d253f94128ad3/fast_bencode-1.1.8.tar.gz";
      hash = "sha256-PHhRcaowoMpnp/JVCNXN+GNrwQk9IbwfJ8LdSS17/LE=";
      nativeBuildInputs = [
        final.cython
        final.setuptools
      ];
      pythonImportsCheck = [ "bencode" ];
    };

    pinyin2hanzi = mkSetuptools {
      pname = "Pinyin2Hanzi";
      version = "0.1.1";
      url = "https://files.pythonhosted.org/packages/04/be/a01db528e5b0870dada638ddbc4a8470c9fa1119a49c651be6b08546a5b0/Pinyin2Hanzi-0.1.1.tar.gz";
      hash = "sha256-g/dsGaOJdCUjNDRSBmrw+s7npbh4RD1xtzb2hnmrzVY=";
      pythonImportsCheck = [ "Pinyin2Hanzi" ];
    };

    aiopathlib = mkPyproject {
      pname = "aiopathlib";
      version = "0.6.0";
      url = "https://files.pythonhosted.org/packages/9b/77/4de0b200a8e841dbf3617cac1fd4b7177e5c7914a4a43bd9397e25bd21c8/aiopathlib-0.6.0.tar.gz";
      hash = "sha256-uEPl78Md8EkpyL1kStwsNHoG9ywQg6kFl2ScNWbdPuo=";
      nativeBuildInputs = [ final."pdm-backend" ];
      propagatedBuildInputs = [ final.aiofiles ];
      pythonImportsCheck = [ "aiopathlib" ];
    };

    aioshutil = mkSetuptools {
      pname = "aioshutil";
      version = "1.5";
      url = "https://files.pythonhosted.org/packages/75/e4/ef86f1777a9bc0c51d50487b471644ae20941afe503591d3a4c86e456dac/aioshutil-1.5.tar.gz";
      hash = "sha256-J1bWzTuwNAXcc0isEaC2DrlJ69Y83RX1bpIkECMcEgE=";
      nativeBuildInputs = [ final."setuptools-scm" ];
      pythonImportsCheck = [ "aioshutil" ];
    };

    asynctempfile = mkSetuptools {
      pname = "asynctempfile";
      version = "0.5.0";
      url = "https://files.pythonhosted.org/packages/23/60/ec51c5e926f4879a6f6817b2d73a775ebc968a555499ff2f6565b3607a7d/asynctempfile-0.5.0.tar.gz";
      hash = "sha256-SmR8dHNX6IJzl7qtvf6H8wldMJI/p4nnlxEesCFgiEo=";
      propagatedBuildInputs = [ final.aiofiles ];
      pythonImportsCheck = [ "asynctempfile" ];
    };

    iso639 = mkSetuptools {
      pname = "iso639";
      version = "0.1.4";
      url = "https://files.pythonhosted.org/packages/d5/23/6aecf85ed735ff017af073d1da764b8f24822f8ec17798fc83816d166826/iso639-0.1.4.tar.gz";
      hash = "sha256-iLcM9sZO6cLClyKSgYyL6zLbnqb03h+EcamwgaPZLpg=";
      pythonImportsCheck = [ "iso639" ];
    };

    gotify = mkPyproject {
      pname = "gotify";
      version = "0.6.0";
      url = "https://files.pythonhosted.org/packages/60/e5/f7d6b37c70adce7533a93aadd9624a67ab79323766c8b3978a6653f16ea8/gotify-0.6.0.tar.gz";
      hash = "sha256-R73AMyFDzVwlHihP+kh0Z0KcYkodQK77ATd09vTdS30=";
      nativeBuildInputs = [ final."flit-core" ];
      propagatedBuildInputs = [ final.httpx ];
      pythonImportsCheck = [ "gotify" ];
    };

    "paho-mqtt" = prev."paho-mqtt".overridePythonAttrs (_: {
      doCheck = false;
    });

    apprise = disableChecks prev.apprise;
    chalice = disableChecks prev.chalice;
    cherrypy = disableChecks prev.cherrypy;
    dateparser = disableChecks prev.dateparser;
    "langchain" = disableChecks prev."langchain";
    "langchain-community" = disableChecks prev."langchain-community";
    "langchain-core" = disableChecks prev."langchain-core";
    "langchain-openai" = disableChecks prev."langchain-openai";
    langgraph = disableChecks prev.langgraph;
    "langgraph-checkpoint" = disableChecks prev."langgraph-checkpoint";
    "langgraph-checkpoint-postgres" = disableChecks prev."langgraph-checkpoint-postgres";
    "langgraph-checkpoint-sqlite" = disableChecks prev."langgraph-checkpoint-sqlite";
    "langgraph-prebuilt" = disableChecks prev."langgraph-prebuilt";
    langsmith = disableChecks prev.langsmith;
    pymediainfo = prev.pymediainfo.overridePythonAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/pymediainfo-filelike-track-compat.patch
      ];
    });
    sanic = disableChecks prev.sanic;
    "slack-bolt" = disableChecks prev."slack-bolt";
    spacy = disableChecks prev.spacy;
    "spacy-loggers" = disableChecks prev."spacy-loggers";
    wandb = disableChecks prev.wandb;

    pypushdeer = mkSetuptools {
      pname = "pypushdeer";
      version = "0.0.3";
      url = "https://files.pythonhosted.org/packages/b7/0c/b9ff1a3bef64eed4f8b4ca78e3f495c86e2c2900240c37fdb1ed3bf8443b/pypushdeer-0.0.3.tar.gz";
      hash = "sha256-i441WVpFxMYkehl2H0ccnVtcjK1sW46AdsjKSG8pv/Y=";
      propagatedBuildInputs = [ final.requests ];
      pythonImportsCheck = [ "pypushdeer" ];
    };

    "langchain-google-genai" = mkPyproject {
      pname = "langchain_google_genai";
      version = "4.2.1";
      url = "https://files.pythonhosted.org/packages/14/63/e7d148f903cebfef50109da71378f411166f068d66f79b9e16a62dbacf41/langchain_google_genai-4.2.1.tar.gz";
      hash = "sha256-f0RIegM3U1iX47upodZgXXImKeA091f/qHVa8KqF2qg=";
      nativeBuildInputs = [ final.hatchling ];
      propagatedBuildInputs = [
        final.filetype
        final."google-genai"
        final."langchain-core"
        final.pydantic
      ];
      pythonImportsCheck = [ "langchain_google_genai" ];
    };

    "pillow-avif-plugin" =
      let
        src = pkgs.runCommand "pillow-avif-plugin-1.5.2-src" { } ''
          mkdir -p "$out/src/pillow_avif"

          cat > "$out/pyproject.toml" <<'EOF'
          [build-system]
          requires = ["setuptools>=68"]
          build-backend = "setuptools.build_meta"

          [project]
          name = "pillow-avif-plugin"
          version = "1.5.2"
          description = "Compatibility stub for Pillow native AVIF support"
          requires-python = ">=3.8"
          dependencies = ["pillow"]
          EOF

          cat > "$out/src/pillow_avif/__init__.py" <<'EOF'
          from PIL import AvifImagePlugin as _AvifImagePlugin  # noqa: F401

          __all__ = []
          __version__ = "1.5.2"
          EOF
        '';
      in
      prev.buildPythonPackage {
        pname = "pillow_avif_plugin";
        version = "1.5.2";
        inherit src;
        pyproject = true;
        nativeBuildInputs = [ final.setuptools ];
        propagatedBuildInputs = [ final.pillow ];
        pythonImportsCheck = [ "pillow_avif" ];
      };
  })
