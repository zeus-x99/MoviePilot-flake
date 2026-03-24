# MoviePilot-flake

这是一个面向 NixOS 的 `MoviePilot` flake 仓库，目标是：

- 使用上游源码仓库作为输入
- 在 Nix 构建期产出固定的后端运行环境、前端静态产物和运行时目录骨架
- 运行时只做本地文件同步，不再 `git clone`、`pip install`、`yarn build`
- 默认关闭运行时资源自更新，并禁用运行时插件 `pip install`

上游来源：

- 安装文档：https://wiki.movie-pilot.org/zh/install
- 后端源码：https://github.com/jxxghp/MoviePilot
- 前端源码：https://github.com/jxxghp/MoviePilot-Frontend
- 官方插件：https://github.com/jxxghp/MoviePilot-Plugins
- 资源仓库：https://github.com/jxxghp/MoviePilot-Resources

## 当前实现

这个仓库把 MoviePilot 拆成了四个 Nix 产物：

- `packages.<system>.moviepilot-python`
  纯 Nix 构建的 Python 运行环境，内含后端依赖和官方插件所需依赖
- `packages.<system>.moviepilot-playwright-driver`
  与 Python 运行环境配套的浏览器二进制
- `packages.<system>.moviepilot-frontend`
  纯 Nix 构建的前端 `dist`
- `packages.<system>.moviepilot-runtime`
  组装后的运行目录骨架，包含后端源码、官方插件、资源文件和前端构建产物

NixOS module 启动时只会把 `moviepilot-runtime` 从 Nix store 同步到 `${stateDir}/runtime`，不会联网构建。

这里仍然保留 `${stateDir}/runtime`，不是因为还在“源码安装”，而是为了兼容 MoviePilot 上游对可写插件目录的假设：

- 官方/第三方插件会写入 `app/plugins`
- 插件分身会原地修改插件文件
- 资源文件也默认按 `ROOT_PATH/app/helper` 组织

也就是说，当前仓库是“纯 Nix 构建 + 运行时可写数据目录兼容层”，不是“运行时再拉源码/装依赖”。

## 目录说明

- `flake.nix`
  flake 输入、包定义、module 导出、同步脚本 app
- `module.nix`
  `services.moviepilot` 的 NixOS module
- `nix/python-packages.nix`
  对 `nixpkgs` 中缺失的 Python 包做补充覆盖
- `nix/frontend.nix`
  前端纯 Nix 构建表达式
- `nix/runtime.nix`
  组装运行目录的表达式
- `nix/sources.nix`
  当前前端离线依赖哈希
- `scripts/update-upstream.sh`
  一键更新上游输入与前端离线依赖哈希

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

配套的环境文件示例：

```env
SUPERUSER_PASSWORD=replace-me
API_TOKEN=replace-with-a-long-random-string
TMDB_API_KEY=replace-me
PROXY_HOST=
```

## NixOS 选项

- `services.moviepilot.enable`
- `services.moviepilot.package`
  默认使用 flake 内置的 `moviepilot-runtime`
- `services.moviepilot.pythonPackage`
  默认使用 flake 内置的 `moviepilot-python`
- `services.moviepilot.playwrightPackage`
  默认使用 flake 内置的 `moviepilot-playwright-driver`
- `services.moviepilot.stateDir`
  默认是 `/var/lib/moviepilot`
- `services.moviepilot.environmentFile`
- `services.moviepilot.settings`
- `services.moviepilot.extraPackages`
  默认带上 `ffmpeg`、`mediainfo`、`rclone`
- `services.moviepilot.backend.port`
  默认 `3001`
- `services.moviepilot.frontend.enable`
- `services.moviepilot.frontend.port`
  默认 `3000`

## 部署

建议顺序：

```bash
nix flake check
sudo nixos-rebuild dry-activate --flake .#YOUR_HOST
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

查看日志：

```bash
journalctl -u moviepilot-prepare -f
journalctl -u moviepilot-backend -f
journalctl -u moviepilot-frontend -f
```

## 同步上游

这个仓库现在把四个上游仓库都放进了 flake inputs，升级时不需要手工 clone：

```bash
nix run .#update-upstream
```

默认行为：

1. 更新 `moviepilotSrc`、`moviepilotFrontendSrc`、`moviepilotPluginsSrc`、`moviepilotResourcesSrc`
2. 重新计算前端 `yarn.lock` 对应的离线依赖哈希，并写回 `nix/sources.nix`
3. 做一次快速校验：
   - `nix build .#packages.<currentSystem>.moviepilot-python --no-link`
   - `nix build .#packages.<currentSystem>.moviepilot-runtime --no-link`
   - `nix eval .#checks.<currentSystem>.module-eval.drvPath`

如果你想跑完整校验，再显式加：

```bash
nix run .#update-upstream -- --full-check
```

如果你只想更新某一部分上游，也可以直接指定组件：

```bash
nix run .#update-upstream -- backend
nix run .#update-upstream -- frontend
nix run .#update-upstream -- plugins resources
```

如果你临时只想更新锁文件，不想当场校验：

```bash
nix run .#update-upstream -- --skip-check
```

如果上游后端新增了全新的 Python 依赖，而 `nixpkgs` 里也没有，就需要补充 `nix/python-packages.nix`。

如果你只想更新某一个上游输入，也可以直接运行：

```bash
nix flake lock --update-input moviepilotSrc
nix flake lock --update-input moviepilotFrontendSrc
nix flake lock --update-input moviepilotPluginsSrc
nix flake lock --update-input moviepilotResourcesSrc
```

## 限制

- 基础运行环境已经是纯 Nix 构建；为了保持这个前提，module 默认会禁用资源自更新，并显式禁止运行时插件 `pip install`。
- 第三方插件若自带新的 `requirements.txt`，不会像 Docker/源码直跑那样自动装进去。
- 官方插件依赖已经预置进 `moviepilot-python`，所以官方插件不依赖运行时 `pip install`。
- 如果你要支持额外第三方插件依赖，建议继续把对应 Python 包声明式加入这个仓库，而不是回退到运行时 `pip install`。
