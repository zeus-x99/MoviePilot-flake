#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'EOF'
用法:
  update-upstream [backend] [frontend] [plugins] [resources] [--skip-check] [--full-check]

说明:
  - 不传组件参数时，默认更新全部上游
  - 只在更新 frontend 时重算 nix/sources.nix 中的 yarn hash
  - 默认执行快速校验
  - --full-check 执行 nix flake check
  - --skip-check 跳过校验
EOF
}

declare -A input_map=(
  [backend]="moviepilotSrc"
  [frontend]="moviepilotFrontendSrc"
  [plugins]="moviepilotPluginsSrc"
  [resources]="moviepilotResourcesSrc"
)

selected_components=()
check_mode="quick"

while (($# > 0)); do
  case "$1" in
    backend|frontend|plugins|resources)
      selected_components+=("$1")
      ;;
    --skip-check)
      check_mode="skip"
      ;;
    --full-check)
      check_mode="full"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if ((${#selected_components[@]} == 0)); then
  selected_components=(backend frontend plugins resources)
fi

lock_args=()
update_frontend_hash=0

for component in "${selected_components[@]}"; do
  lock_args+=(--update-input "${input_map[$component]}")
  if [[ "$component" == "frontend" ]]; then
    update_frontend_hash=1
  fi
done

echo "==> 更新上游输入: ${selected_components[*]}"
nix flake lock "${lock_args[@]}"

if ((update_frontend_hash)); then
  echo "==> 刷新前端 yarn hash"
  frontend_src="$(nix eval --raw .#lib.sources.frontend)"
  frontend_yarn_hash_raw="$(prefetch-yarn-deps "$frontend_src/yarn.lock")"
  frontend_yarn_hash="$(nix hash convert --hash-algo sha256 --to sri "$frontend_yarn_hash_raw")"

  sed -i -E \
    "s#frontendYarnHash = \".*\";#frontendYarnHash = \"${frontend_yarn_hash}\";#" \
    nix/sources.nix
fi

case "$check_mode" in
  skip)
    echo "==> 跳过校验"
    ;;
  full)
    echo "==> 执行完整校验: nix flake check"
    nix flake check
    ;;
  quick)
    system="$(nix eval --impure --raw --expr builtins.currentSystem)"
    echo "==> 执行快速校验: ${system}"
    nix build ".#packages.${system}.moviepilot-python" --no-link
    nix build ".#packages.${system}.moviepilot-runtime" --no-link
    nix eval ".#checks.${system}.module-eval.drvPath" >/dev/null
    ;;
esac
