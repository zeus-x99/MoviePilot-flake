#!/usr/bin/env bash
set -euo pipefail

resolve_repo_root() {
  local cwd_root script_root

  if cwd_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    if [[ -f "$cwd_root/flake.nix" && -f "$cwd_root/flake.lock" && -f "$cwd_root/scripts/update-upstream.sh" ]]; then
      printf '%s\n' "$cwd_root"
      return
    fi
  fi

  script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ -f "$script_root/flake.nix" && -f "$script_root/flake.lock" && -f "$script_root/scripts/update-upstream.sh" ]]; then
    printf '%s\n' "$script_root"
    return
  fi

  echo "错误: 找不到 MoviePilotNix 仓库根目录；请在仓库工作树中运行该脚本。" >&2
  exit 1
}

repo_root="$(resolve_repo_root)"
cd "$repo_root"

official_version() {
  nix eval --raw .#lib.version
}

original_field() {
  local input="$1"
  local field="$2"
  jq -r --arg input "$input" --arg field "$field" '
    .nodes[$input].original[$field] // ""
  ' flake.lock
}

input_ref() {
  local input="$1"
  local type owner repo ref url

  type="$(original_field "$input" type)"
  owner="$(original_field "$input" owner)"
  repo="$(original_field "$input" repo)"
  ref="$(original_field "$input" ref)"
  url="$(original_field "$input" url)"

  if [[ -z "$type" ]]; then
    type="$(lock_field "$input" type)"
  fi
  if [[ -z "$owner" ]]; then
    owner="$(lock_field "$input" owner)"
  fi
  if [[ -z "$repo" ]]; then
    repo="$(lock_field "$input" repo)"
  fi

  case "$type" in
    github)
      if [[ -n "$ref" ]]; then
        printf 'github:%s/%s/%s\n' "$owner" "$repo" "$ref"
      else
        printf 'github:%s/%s\n' "$owner" "$repo"
      fi
      ;;
    *)
      if [[ -n "$url" ]]; then
        printf '%s\n' "$url"
      else
        echo "错误: 无法为输入 $input 解析上游引用。" >&2
        exit 1
      fi
      ;;
  esac
}

upstream_official_version() {
  local frontend_ref frontend_src

  frontend_ref="$(input_ref moviepilotFrontendSrc)"
  frontend_src="$(
    nix flake prefetch --json --refresh "$frontend_ref" \
      | jq -r '.storePath'
  )"

  jq -r '.version' "$frontend_src/package.json"
}

usage() {
  cat <<'EOF'
用法:
  update-upstream [backend] [frontend] [plugins] [resources] [--skip-check] [--full-check] [--allow-dirty]

说明:
  - 不传组件参数时，默认更新全部上游
  - 只在更新 frontend 时重算 nix/sources.nix 中的 yarn hash
  - 默认按所选组件执行最小必要的快速校验
  - --full-check 执行 nix flake check
  - --skip-check 跳过校验
  - 默认要求仓库工作树干净；如确需带本地改动运行，显式传入 --allow-dirty
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
allow_dirty=0
declare -A seen_components=()
selected_inputs=()
build_targets=()
check_targets=()
# shellcheck disable=SC2034
declare -A seen_build_targets=()
# shellcheck disable=SC2034
declare -A seen_check_targets=()

short_ref() {
  local value="$1"
  if [[ "$value" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s' "${value:0:12}"
  else
    printf '%s' "$value"
  fi
}

lock_field() {
  local input="$1"
  local field="$2"
  jq -r --arg input "$input" --arg field "$field" '
    .nodes[$input].locked[$field] // .nodes[$input].original[$field] // ""
  ' flake.lock
}

describe_lock_input() {
  local input="$1"
  local owner repo rev ref url type
  owner="$(lock_field "$input" owner)"
  repo="$(lock_field "$input" repo)"
  rev="$(lock_field "$input" rev)"
  ref="$(lock_field "$input" ref)"
  url="$(lock_field "$input" url)"
  type="$(lock_field "$input" type)"

  if [[ -n "$owner" && -n "$repo" ]]; then
    if [[ -n "$rev" ]]; then
      printf '%s/%s@%s' "$owner" "$repo" "$(short_ref "$rev")"
    elif [[ -n "$ref" ]]; then
      printf '%s/%s#%s' "$owner" "$repo" "$ref"
    else
      printf '%s/%s' "$owner" "$repo"
    fi
  elif [[ -n "$url" ]]; then
    if [[ -n "$rev" ]]; then
      printf '%s@%s' "$url" "$(short_ref "$rev")"
    else
      printf '%s' "$url"
    fi
  elif [[ -n "$type" ]]; then
    if [[ -n "$rev" ]]; then
      printf '%s@%s' "$type" "$(short_ref "$rev")"
    elif [[ -n "$ref" ]]; then
      printf '%s#%s' "$type" "$ref"
    else
      printf '%s' "$type"
    fi
  else
    printf '<unknown>'
  fi
}

show_locked_inputs() {
  local title="$1"
  local component input summary

  echo "==> ${title}"
  for component in "${selected_components[@]}"; do
    input="${input_map[$component]}"
    summary="$(describe_lock_input "$input")"
    echo "  - ${component}: ${summary}"
  done
}

ensure_clean_worktree() {
  local status

  status="$(git status --short --untracked-files=all)"
  if [[ -n "$status" ]]; then
    echo "错误: 当前仓库存在未提交改动，拒绝更新上游以免把本地改动混入同步结果。" >&2
    echo "$status" >&2
    echo "如确需继续，请显式传入 --allow-dirty。" >&2
    exit 1
  fi
}

add_unique_item() {
  local -n seen_ref="$1"
  local -n array_ref="$2"
  local value="$3"

  if [[ -z "${seen_ref[$value]:-}" ]]; then
    seen_ref["$value"]=1
    array_ref+=("$value")
  fi
}

add_build_target() {
  add_unique_item seen_build_targets build_targets "$1"
}

add_check_target() {
  add_unique_item seen_check_targets check_targets "$1"
}

while (($# > 0)); do
  case "$1" in
    backend|frontend|plugins|resources)
      if [[ -z "${seen_components[$1]:-}" ]]; then
        selected_components+=("$1")
        seen_components["$1"]=1
      fi
      ;;
    --skip-check)
      check_mode="skip"
      ;;
    --full-check)
      check_mode="full"
      ;;
    --allow-dirty)
      allow_dirty=1
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

if ((allow_dirty)); then
  echo "==> 已启用 --allow-dirty，跳过工作树清洁检查"
else
  ensure_clean_worktree
fi

version_before="$(official_version)"
version_upstream="$(upstream_official_version)"

echo "==> 当前官方版本: ${version_before}"
echo "==> 上游官方版本: ${version_upstream}"

if [[ "$version_before" == "$version_upstream" ]]; then
  echo "==> 官方版本未变化 (${version_before})，跳过本次同步"
  exit 0
fi

flake_lock_snapshot="$(mktemp)"
sources_snapshot="$(mktemp)"
cleanup_snapshots() {
  rm -f "$flake_lock_snapshot" "$sources_snapshot"
}
trap cleanup_snapshots EXIT

cp flake.lock "$flake_lock_snapshot"
cp nix/sources.nix "$sources_snapshot"

update_frontend_hash=0

for component in "${selected_components[@]}"; do
  selected_inputs+=("${input_map[$component]}")
  if [[ "$component" == "frontend" ]]; then
    update_frontend_hash=1
  fi
done

echo "==> 更新上游输入: ${selected_components[*]}"
show_locked_inputs "更新前锁定版本"
nix flake update "${selected_inputs[@]}"
show_locked_inputs "更新后锁定版本"

version_after="$(official_version)"

if [[ "$version_before" == "$version_after" ]]; then
  echo "==> 官方版本未变化 (${version_before})，跳过本次同步并恢复锁定文件"
  cp "$flake_lock_snapshot" flake.lock
  cp "$sources_snapshot" nix/sources.nix
  exit 0
fi

echo "==> 官方版本变化: ${version_before} -> ${version_after}"

if ((update_frontend_hash)); then
  echo "==> 刷新前端 yarn hash"
  frontend_yarn_hash_before="$(
    sed -n -E 's#^[[:space:]]*frontendYarnHash = "(.*)";#\1#p' nix/sources.nix
  )"
  frontend_src="$(nix eval --raw .#lib.sources.frontend)"
  frontend_yarn_hash_raw="$(prefetch-yarn-deps "$frontend_src/yarn.lock")"
  frontend_yarn_hash="$(nix hash convert --hash-algo sha256 --to sri "$frontend_yarn_hash_raw")"

  if [[ "$frontend_yarn_hash_before" != "$frontend_yarn_hash" ]]; then
    sed -i -E \
      "s#frontendYarnHash = \".*\";#frontendYarnHash = \"${frontend_yarn_hash}\";#" \
      nix/sources.nix
    echo "  - frontendYarnHash: ${frontend_yarn_hash_before} -> ${frontend_yarn_hash}"
  else
    echo "  - frontendYarnHash: 未变化 (${frontend_yarn_hash})"
  fi
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
    add_check_target ".#checks.${system}.module-eval"
    add_check_target ".#checks.${system}.example-eval"
    add_build_target ".#packages.${system}.moviepilot-runtime"

    for component in "${selected_components[@]}"; do
      case "$component" in
        backend)
          add_build_target ".#packages.${system}.moviepilot-python"
          add_build_target ".#packages.${system}.moviepilot-backend"
          if [[ "$system" == "x86_64-linux" ]]; then
            add_check_target ".#checks.${system}.nixos-test"
            add_check_target ".#checks.${system}.nixos-test-no-frontend"
          fi
          ;;
        frontend)
          add_build_target ".#packages.${system}.moviepilot-frontend"
          if [[ "$system" == "x86_64-linux" ]]; then
            add_check_target ".#checks.${system}.nixos-test"
          fi
          ;;
        plugins)
          add_build_target ".#packages.${system}.moviepilot-python"
          add_build_target ".#packages.${system}.moviepilot-plugins"
          add_build_target ".#packages.${system}.moviepilot-frontend"
          if [[ "$system" == "x86_64-linux" ]]; then
            add_check_target ".#checks.${system}.nixos-test"
          fi
          ;;
        resources)
          add_build_target ".#packages.${system}.moviepilot-resources"
          if [[ "$system" == "x86_64-linux" ]]; then
            add_check_target ".#checks.${system}.nixos-test"
          fi
          ;;
      esac
    done

    if ((${#build_targets[@]} > 0)); then
      echo "==> 构建目标:"
      printf '  - %s\n' "${build_targets[@]}"
      for target in "${build_targets[@]}"; do
        nix build "$target" --no-link
      done
    fi

    if ((${#check_targets[@]} > 0)); then
      echo "==> 校验目标:"
      printf '  - %s\n' "${check_targets[@]}"
      for target in "${check_targets[@]}"; do
        nix build "$target" --no-link
      done
    fi
    ;;
esac
