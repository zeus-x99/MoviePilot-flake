# MoviePilotNix

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

这个仓库把 MoviePilot 拆成了多层 Nix 产物：

- `packages.<system>.moviepilot-python`
  纯 Nix 构建的 Python 运行环境，内含后端依赖和官方插件所需依赖
- `packages.<system>.moviepilot-playwright-driver`
  与 Python 运行环境配套的浏览器二进制
- `packages.<system>.moviepilot-backend`
  纯 Nix 构建的后端源码树，已带上纯 Nix 运行补丁
- `packages.<system>.moviepilot-plugins`
  官方插件集合
- `packages.<system>.moviepilot-resources`
  资源文件集合
- `packages.<system>.moviepilot-frontend`
  纯 Nix 构建的前端 `dist`，以及运行上游 `service.js` 所需的最小 Node 依赖
- `packages.<system>.moviepilot-runtime`
  运行目录聚合包，方便手工查看完整运行目录骨架

NixOS module 启动时会把 backend/plugins/resources/frontend 分层同步到 `${stateDir}` 下，避免插件或资源更新时整棵 backend 目录全量重刷，也不会联网构建。

flake 还额外导出了 `lib.sourceRevisions` 和 `lib.packageVersions`，方便你在 review 或调试时直接看到当前锁定的上游 revision 与对应包版本。

这里仍然保留 `${stateDir}/runtime`，不是因为还在“源码安装”，而是为了适配 MoviePilot 上游对可写插件目录的假设：

- 官方/第三方插件会写入 `app/plugins`
- 插件分身会原地修改插件文件
- 资源文件也默认按 `ROOT_PATH/app/helper` 组织

也就是说，当前仓库是“纯 Nix 构建 + 运行时可写数据目录适配层”，不是“运行时再拉源码/装依赖”。

## 目录说明

- `flake.nix`
  flake 输入、包定义、module 导出、同步脚本 app
- `examples/flake.nix`
  一个可直接参考的宿主机 flake 示例
- `examples/moviepilot.env.example`
  最小环境变量示例
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
    moviepilotNix.url = "github:zeus-x99/MoviePilotNix";
  };

  outputs = { self, nixpkgs, moviepilotNix, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        moviepilotNix.nixosModules.default
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

仓库里也附带了现成示例：

- `examples/flake.nix`
- `examples/moviepilot.env.example`

如果你已经有自己的系统 flake，最小接入只需要两步：

1. 在 `inputs` 里加入 `moviepilotNix.url = "github:zeus-x99/MoviePilotNix";`
2. 在对应主机的 `modules` 里加入 `moviepilotNix.nixosModules.default`

然后执行：

```bash
sudo nixos-rebuild dry-activate --flake .#YOUR_HOST
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

## NixOS 选项

- `services.moviepilot.enable`
- `services.moviepilot.backendPackage`
  默认使用 flake 内置的 `moviepilot-backend`
- `services.moviepilot.pluginsPackage`
  默认使用 flake 内置的 `moviepilot-plugins`
- `services.moviepilot.resourcesPackage`
  默认使用 flake 内置的 `moviepilot-resources`
- `services.moviepilot.pythonPackage`
  默认使用 flake 内置的 `moviepilot-python`
- `services.moviepilot.playwrightBrowsersPath`
  默认自动解析 flake 内置 playwright 浏览器目录
  如果手工传字符串，必须使用绝对路径
  更推荐直接传浏览器目录路径，例如 `pkgs.playwright-driver.browsers`
- `services.moviepilot.stateDir`
  默认是 `/var/lib/moviepilot`
  不能放到 `/nix/store` 这类只读路径
  如果放在 `/home`、`/root` 或 `/run/user` 下，模块会自动禁用 `ProtectHome`
- `services.moviepilot.host`
  frontend 开启时默认是 `127.0.0.1`，只让 backend 监听本机
  frontend 关闭时默认是 `0.0.0.0`
  如果你显式改成 `0.0.0.0`，backend 也会直接监听外部接口
- `services.moviepilot.openFirewall`
  为 `true` 时只开放当前对外服务端口
  frontend 开启时开放 `services.moviepilot.frontend.port`
  frontend 关闭时开放 `services.moviepilot.backend.port`
- `services.moviepilot.environmentFile`
  建议放在 `/run/secrets` 一类的运行时路径，不要把密钥文件做进 `/nix/store`
- `services.moviepilot.settings`
- `services.moviepilot.extraPackages`
  默认带上 `ffmpeg`、`mediainfo`、`rclone`
- `services.moviepilot.backend.port`
  默认 `3001`
- `services.moviepilot.backend.allowedDevices`
  默认 `[]`
  兼容简单字符串写法，例如 `[ "/dev/dri/renderD128" "/dev/dri/card0" ]`
  也支持按设备指定权限模式，例如 `[ { path = "/dev/video0"; permissions = "r"; } ]`
  非空时 backend 会用 `DevicePolicy=closed` + `DeviceAllow` 只放行这些设备
  `permissions` 目前支持 `r`、`rw`、`rwm`
  如果同一路径重复声明，模块会给 warning；若 permissions 冲突，会自动收敛到更宽权限
- `services.moviepilot.backend.supplementaryGroups`
  默认 `[]`
  如果设备节点权限依赖组，例如 `/dev/dri/*` 常见需要 `render`，`/dev/video*` 常见需要 `video`
- `services.moviepilot.frontend.enable`
- `services.moviepilot.frontend.port`
  默认 `3000`

## 部署

建议顺序：

```bash
nix build .#packages.x86_64-linux.moviepilot-python --no-link
nix build .#packages.x86_64-linux.moviepilot-backend --no-link
nix build .#packages.x86_64-linux.moviepilot-plugins --no-link
nix build .#packages.x86_64-linux.moviepilot-resources --no-link
nix build .#packages.x86_64-linux.moviepilot-frontend --no-link
nix build .#packages.x86_64-linux.moviepilot-runtime --no-link
nix eval .#checks.x86_64-linux.module-eval.drvPath
sudo nixos-rebuild dry-activate --flake .#YOUR_HOST
sudo nixos-rebuild switch --flake .#YOUR_HOST
```

如果你要做完整校验，再补一轮：

```bash
nix flake check
```

查看日志：

```bash
journalctl -u moviepilot-prepare -f
journalctl -u moviepilot-backend -f
journalctl -u moviepilot-frontend -f
```

当前前端运行模型是：

- 构建期仍然使用 `node + yarn`
- 运行期由 `node service.js` 托管前端静态文件和反代
- 没有修改上游前端源码，只是在打包时额外带上运行 `service.js` 所需的最小 `node_modules`

如果你是从旧版本迁移，历史上遗留的 root-owned `stateDir` 内容会在 activation/boot 时由 tmpfiles 自动递归修正归属；如果想立刻手工触发一次，可执行：

```bash
sudo systemd-tmpfiles --create --prefix /var/lib/moviepilot
```

如果你改过 `services.moviepilot.stateDir`，把上面的路径替换成你自己的状态目录。

硬件加速常见写法：

```nix
services.moviepilot.backend.allowedDevices = [
  {
    path = "/dev/dri/renderD128";
    permissions = "rw";
  }
  {
    path = "/dev/dri/card0";
    permissions = "rw";
  }
];
services.moviepilot.backend.supplementaryGroups = [ "render" "video" ];
```

## 同步上游

这个仓库现在把四个上游仓库都放进了 flake inputs，升级时不需要手工 clone：

```bash
nix run .#update-upstream
```

默认行为：

1. 更新 `moviepilotSrc`、`moviepilotFrontendSrc`、`moviepilotPluginsSrc`、`moviepilotResourcesSrc`
2. 输出所选上游输入的更新前/更新后锁定 revision，便于你直接 review 和提交
3. 只有当上游声明的官方版本号发生变化时，才会保留这次同步结果；如果只是同版本下的 commit 漂移，脚本会自动恢复 `flake.lock` 和 `nix/sources.nix`
4. 重新计算前端 `yarn.lock` 对应的离线依赖哈希，并写回 `nix/sources.nix`
   如果 hash 没变化，脚本会直接提示未变化
5. 自动去重重复组件参数，避免重复执行同一个 `--update-input`
6. 按所选组件做一次快速校验，只跑最小必要的构建/测试集合
   总是包含 `nix build .#checks.<currentSystem>.module-eval --no-link`
   以及 `nix build .#checks.<currentSystem>.example-eval --no-link`
   `backend` 会额外校验 `moviepilot-python`、`moviepilot-backend`、`moviepilot-runtime`，x86_64-linux 下再跑 `nixos-test` 与 `nixos-test-no-frontend`
   `frontend` 会额外校验 `moviepilot-frontend`、`moviepilot-runtime`，x86_64-linux 下再跑 `nixos-test`
   `plugins` 会额外校验 `moviepilot-python`、`moviepilot-plugins`、`moviepilot-frontend`、`moviepilot-runtime`，x86_64-linux 下再跑 `nixos-test`
   `resources` 会额外校验 `moviepilot-resources`、`moviepilot-runtime`，x86_64-linux 下再跑 `nixos-test`

默认还会要求当前仓库工作树是干净的，避免把本地未提交改动和上游同步结果混在一起；如果你明确知道自己在做什么，可以显式传：

```bash
nix run .#update-upstream -- --allow-dirty --skip-check
```

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

脚本输出里你会直接看到类似：

```text
==> 更新前锁定版本
  - backend: jxxghp/MoviePilot@abcdef123456
==> 更新后锁定版本
  - backend: jxxghp/MoviePilot@fedcba654321
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

## GitHub Actions

仓库现在附带两套工作流：

- `.github/workflows/ci.yml`
  在 `push`、`pull_request`、手动触发时执行轻量校验：module/example eval、`update-upstream` 脚本检查，以及 `moviepilot-python` / `moviepilot-runtime` 构建
- `.github/workflows/update-upstream.yml`
  每 4 小时自动执行一次 `nix run .#update-upstream`，只有官方版本号变化时才会开 PR；定时任务默认跳过重校验，验证交给 PR 上的 `CI`，手动触发时仍可传组件列表和校验模式
- `.github/workflows/auto-merge-upstream.yml`
  当 `automation/update-upstream` 这条 PR 的 `CI` 成功后，自动 squash merge 并删除分支

如果你要让自动 PR 正常工作，需要在 GitHub 仓库里打开：

1. `Settings -> Actions -> General -> Workflow permissions`
2. 选择 `Read and write permissions`
3. 勾选 `Allow GitHub Actions to create and approve pull requests`

如果你希望 `Update Upstream` 自动创建的 PR 也能自动触发后续 `CI`，再额外创建一个仓库 secret：

- 名称：`MOVIEPILOTNIX_ACTIONS_PAT`
- 内容：你自己的 GitHub PAT
- 最少需要 `repo` 和 `workflow` 权限

没有这个 secret 时，工作流仍然会正常开 PR，只是 GitHub 的默认 `GITHUB_TOKEN` 创建的 PR 不会再触发新的 workflow run，也无法形成“自动开 PR -> 自动跑 CI -> 自动合并”的闭环。

手动触发 `Update Upstream` 时：

- `components`
  传空格分隔的组件列表，例如 `backend frontend`
- `check_mode`
  可选 `quick`、`full`、`skip`

推荐用法：

- 平时靠定时任务自动开 PR
- PR 上由 `CI` 跑完整 `flake check`
- 你只在 PR 里 review `flake.lock` / `nix/sources.nix`
- 如果上游打破了打包，再在 PR 分支里补 Nix 修复

## 限制

- 基础运行环境已经是纯 Nix 构建；为了保持这个前提，module 默认会禁用资源自更新，并显式禁止运行时插件 `pip install`。
- 第三方插件若自带新的 `requirements.txt`，不会像 Docker/源码直跑那样自动装进去。
- 官方插件依赖已经预置进 `moviepilot-python`，所以官方插件不依赖运行时 `pip install`。
- 如果你要支持额外第三方插件依赖，建议继续把对应 Python 包声明式加入这个仓库，而不是回退到运行时 `pip install`。
