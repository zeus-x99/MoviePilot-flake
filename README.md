# MoviePilot-flake

这个仓库把 MoviePilot 官方“源码安装”流程整理成了一个可直接引用的 NixOS flake module。

设计取舍很直接：

- 上游源码安装要求同时处理 `MoviePilot`、`MoviePilot-Frontend`、`MoviePilot-Plugins`、`MoviePilot-Resources` 四个仓库。
- 后端运行时会写 `app/plugins`，资源更新也会写 `app/helper`。这类路径在纯 Nix store 中不可写，所以这里没有强行做成“只读 derivation + 纯打包”。
- 当前实现采用“由 NixOS 管理依赖与 systemd，首次启动/重启时在状态目录拉源码并构建”的方式，尽量贴近上游源码运行逻辑，也保留插件安装与资源更新能力。

上游依据：

- 官方安装页：https://wiki.movie-pilot.org/zh/install
- 后端 README：https://github.com/jxxghp/MoviePilot
- 前端 README：https://github.com/jxxghp/MoviePilot-Frontend

## 提供内容

- `nixosModules.default`
- `services.moviepilot.enable`
- `moviepilot-prepare`：拉取/更新源码、创建 venv、安装 Python 依赖、同步插件与资源、构建前端
- `moviepilot-backend`：启动 `python -m app.main`
- `moviepilot-frontend`：启动 `node dist/service.js`

## 使用方式

在你的系统 flake 中引用：

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    moviepilotFlake.url = "github:zeus-x99/MoviePilot-flake";
  };

  outputs = { self, nixpkgs, moviepilotFlake, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        moviepilotFlake.nixosModules.default
        ({ ... }: {
          services.moviepilot = {
            enable = true;
            openFirewall = true;
            environmentFile = "/run/secrets/moviepilot.env";
            settings = {
              SUPERUSER = "admin";
            };
          };

          system.stateVersion = "25.05";
        })
      ];
    };
  };
}
```

配套的 `environmentFile` 可以放敏感配置，例如：

```env
SUPERUSER_PASSWORD=replace-me
API_TOKEN=replace-with-a-long-random-string
TMDB_API_KEY=replace-me
PROXY_HOST=
```

## 常用选项

- `services.moviepilot.stateDir`
  默认：`/var/lib/moviepilot`
- `services.moviepilot.host`
  默认：`0.0.0.0`
- `services.moviepilot.backend.port`
  默认：`3001`
- `services.moviepilot.frontend.enable`
  默认：`true`
- `services.moviepilot.frontend.port`
  默认：`3000`
- `services.moviepilot.openFirewall`
  默认：`false`
- `services.moviepilot.settings`
  用于写入非敏感环境变量
- `services.moviepilot.environmentFile`
  用于注入敏感环境变量
- `services.moviepilot.sources.*`
  可分别覆盖四个上游仓库的 `url` / `ref`

默认源如下：

- backend: `https://github.com/jxxghp/MoviePilot.git` @ `v2`
- frontend: `https://github.com/jxxghp/MoviePilot-Frontend.git` @ `v2`
- plugins: `https://github.com/jxxghp/MoviePilot-Plugins.git` @ `main`
- resources: `https://github.com/jxxghp/MoviePilot-Resources.git` @ `main`

## 部署

首次部署建议：

```bash
nix flake check
sudo nixos-rebuild dry-activate --flake .#YOUR_HOST
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

首次启动会比较慢，因为需要：

- 拉取四个上游仓库
- 创建 Python venv 并安装依赖
- 执行 `yarn install`
- 构建前端

查看日志：

```bash
journalctl -u moviepilot-prepare -f
journalctl -u moviepilot-backend -f
journalctl -u moviepilot-frontend -f
```

如果你让 `sources.*.ref` 指向分支名，后续重启服务时会自动拉取该分支最新提交。

## 已知限制

- 这是“源码运行 + NixOS 编排”，不是纯 Nix 打包。
- Python 与 Node 依赖在目标机器的 `stateDir` 下安装，不会进 Nix store。
- 首次启动依赖外网访问 GitHub、PyPI、npm registry。
- 某些 Playwright 相关功能依赖目标系统本身的浏览器运行环境；模块已设置 `PLAYWRIGHT_BROWSERS_PATH`，但是否满足你的使用场景仍要以实际日志为准。
