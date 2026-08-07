#!/usr/bin/env bash
###############################################################################
# sync-upstream.sh
# 同步官方 Supervisor 代码并修复国内源 sed 替换规则
#
# 用法:
#   # 完整执行（交互式，遇到冲突会暂停）
#   GH_TOKEN=ghp_xxx bash script/sync-upstream.sh
#
#   # 指定目标版本
#   GH_TOKEN=ghp_xxx TARGET_TAG=2026.07.5 bash script/sync-upstream.sh
#
#   # 仅执行某个阶段
#   GH_TOKEN=ghp_xxx bash script/sync-upstream.sh --phase 2
#   GH_TOKEN=ghp_xxx bash script/sync-upstream.sh --phase 3
#
# 前置条件:
#   - 当前目录为 supervisor 仓库根目录
#   - 已配置 git 凭据（GH_TOKEN 环境变量或 git credential helper）
#   - 网络可访问 github.com（可能需要代理）
###############################################################################
set -euo pipefail

# ===========================================================================
# 配置
# ===========================================================================
OFFICIAL_REMOTE_NAME="upstream"
OFFICIAL_REPO_URL="https://github.com/home-assistant/supervisor.git"
CN_REPO_URL="https://github.com/home-assistant-cn/supervisor.git"
TARGET_TAG="${TARGET_TAG:-2026.07.5}"
BRANCH_NAME="${BRANCH_NAME:-sync-${TARGET_TAG}}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_TOKEN="${GH_TOKEN:-}"

# 网络问题处理：跳过 SSL 验证（DevSidecar 代理会导致证书验证失败）
export GIT_SSL_NO_VERIFY=1

# ===========================================================================
# 颜色输出
# ===========================================================================
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
blue()   { printf '\033[34m%s\033[0m\n' "$*"; }
header() { printf '\n\033[1;36m========== %s ==========\033[0m\n' "$*"; }

# ===========================================================================
# 阶段 1：创建分支并同步官方代码
# ===========================================================================
phase1_sync() {
    header "阶段 1：创建分支并同步官方代码"

    cd "$PROJECT_DIR"

    # 1.1 确保在 main 分支且是最新的
    blue ">> 切换到 main 分支并拉取最新代码"
    git checkout main
    # 使用 token 拉取（如果提供了）
    if [ -n "$GH_TOKEN" ]; then
        git -c credential.helper='!f() { echo "username=x-access-token"; echo "password='"$GH_TOKEN"'"; }; f' pull origin main || true
    else
        git pull origin main || true
    fi

    # 1.2 创建新分支
    if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
        yellow ">> 分支 ${BRANCH_NAME} 已存在，切换到该分支"
        git checkout "$BRANCH_NAME"
    else
        blue ">> 创建新分支: ${BRANCH_NAME}"
        git checkout -b "$BRANCH_NAME"
    fi

    # 1.3 添加官方仓库作为 remote
    if git remote get-url "$OFFICIAL_REMOTE_NAME" >/dev/null 2>&1; then
        yellow ">> upstream remote 已存在，更新中..."
        git remote set-url "$OFFICIAL_REMOTE_NAME" "$OFFICIAL_REPO_URL"
    else
        blue ">> 添加 upstream remote: ${OFFICIAL_REPO_URL}"
        git remote add "$OFFICIAL_REMOTE_NAME" "$OFFICIAL_REPO_URL"
    fi

    # 1.4 fetch 官方代码
    blue ">> 拉取官方 ${TARGET_TAG} 代码..."
    git fetch "$OFFICIAL_REMOTE_NAME" "$TARGET_TAG" || {
        yellow ">> fetch tag 失败，尝试 fetch main 分支..."
        git fetch "$OFFICIAL_REMOTE_NAME" main
    }

    # 1.5 合并官方代码（会有大量冲突，需要手动解决）
    blue ">> 开始合并官方 ${TARGET_TAG} 代码..."
    yellow ">> ⚠️ 这会产生大量合并冲突（8 个月差异 + addon→app 重命名）"
    yellow ">> ⚠️ 请手动解决冲突后，运行以下命令继续："
    yellow ">>    git add ."
    yellow ">>    git commit"
    yellow ">>    GH_TOKEN=xxx bash script/sync-upstream.sh --phase 2"
    echo ""

    if git merge "$OFFICIAL_REMOTE_NAME/$TARGET_TAG" --no-edit 2>/dev/null; then
        green ">> 合并成功，无冲突！"
    else
        red ">> 合并过程中出现冲突，请手动解决以下文件的冲突："
        git diff --name-only --diff-filter=U | while read -r file; do
            echo "    - $file"
        done
        echo ""
        yellow ">> 解决冲突后，继续执行阶段 2："
        yellow ">>    git add . && git commit"
        yellow ">>    GH_TOKEN=xxx bash script/sync-upstream.sh --phase 2"
        exit 1
    fi
}

# ===========================================================================
# 阶段 2：修复 builder.yml（sed 命令目标文件）
# ===========================================================================
phase2_fix_builder() {
    header "阶段 2：修复 builder.yml"

    cd "$PROJECT_DIR"
    local builder_yml=".github/workflows/builder.yml"

    if [ ! -f "$builder_yml" ]; then
        red ">> 错误: ${builder_yml} 不存在"
        exit 1
    fi

    blue ">> 修复 1: 移除 sed 命令中的 build.yaml（官方已删除该文件）"
    # 原: sed -i ${{ vars.REPLACE_REPOSITORY_NAME }} build.yaml pyproject.toml
    # 新: sed -i ${{ vars.REPLACE_REPOSITORY_NAME }} pyproject.toml
    # 两处（L103 和 L259）都会被替换
    sed -i 's|sed -i \${{ vars.REPLACE_REPOSITORY_NAME }} build.yaml pyproject.toml|sed -i ${{ vars.REPLACE_REPOSITORY_NAME }} pyproject.toml|g' "$builder_yml"
    green "   已移除 sed 命令中的 build.yaml 目标（2 处）"

    blue ">> 修复 2: 移除条件检查中的 build.yaml 引用"
    # 原: if [[ ... =~ (requirements.txt|build.yaml) ]]; then
    # 新: if [[ ... =~ (requirements.txt) ]]; then
    # 使用 @ 作为分隔符，避免与模式中的 | 冲突
    sed -i 's@(requirements.txt|build.yaml)@(requirements.txt)@g' "$builder_yml"
    green "   已移除条件检查中的 build.yaml 引用"

    blue ">> 修复 3: 确认 ADDONS_SOURCE 目标为 store/const.py"
    # 这在之前的提交 34c06c9e9 中已修复，这里只是验证
    if grep -q 'sed -i \${{ vars.ADDONS_SOURCE }} supervisor/store/const.py' "$builder_yml"; then
        green "   已确认: ADDONS_SOURCE 目标为 store/const.py"
    else
        yellow "   ⚠️ ADDONS_SOURCE 目标可能需要检查"
        grep 'ADDONS_SOURCE' "$builder_yml" || true
    fi

    blue ">> 检查: 验证各 sed 目标文件是否存在"
    local sed_targets=(
        "supervisor/const.py"
        "supervisor/store/const.py"
        "pyproject.toml"
        "supervisor/os/manager.py"
        "supervisor/docker/interface.py"
        "supervisor/utils/sentry.py"
        "Dockerfile"
    )
    for target in "${sed_targets[@]}"; do
        if [ -f "$target" ]; then
            green "   ✅ ${target}"
        else
            red "   ❌ ${target} 不存在！需要检查构建流程"
        fi
    done

    echo ""
    yellow ">> ⚠️ 注意事项："
    yellow ">> 1. 官方新版 Dockerfile 改为多阶段构建，builder.yml 中的"
    yellow ">>    'Build supervisor' 步骤可能需要从 home-assistant/builder 改为"
    yellow ">>    docker buildx build。请根据合并后的代码状态评估。"
    yellow ">> 2. 官方新版废弃了 build.yaml，镜像名定义可能在代码中。"
    yellow ">>    确认 GHCR_DOWNLOAD_SOURCE 的运行时替换逻辑仍然有效。"
    echo ""
    green ">> 阶段 2 完成。请检查改动后提交："
    green ">>    git diff ${builder_yml}"
    green ">>    git add ${builder_yml} && git commit -m '修复 builder.yml sed 目标'"
}

# ===========================================================================
# 阶段 3：通过 API 更新 GitHub 仓库变量
# ===========================================================================
phase3_update_vars() {
    header "阶段 3：更新 GitHub 仓库变量"

    if [ -z "$GH_TOKEN" ]; then
        red ">> 错误: 需要设置 GH_TOKEN 环境变量"
        red ">> 用法: GH_TOKEN=ghp_xxx bash script/sync-upstream.sh --phase 3"
        exit 1
    fi

    yellow ">> ⚠️ 此操作会修改仓库级变量，影响所有分支的构建。"
    yellow ">> ⚠️ 请确认已在 ${BRANCH_NAME} 分支上完成代码合并和测试后执行。"
    yellow ">> ⚠️ 建议先在分支上触发测试构建，验证通过后再更新变量。"
    echo ""
    read -rp ">> 确认要更新 GitHub 仓库变量吗？(yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        yellow ">> 已取消"
        exit 0
    fi

    # 通过环境变量传递 token，heredoc 传递 Python 代码（避免 shell 转义问题）
    export GH_TOKEN
    python3 << 'PYEOF'
import json, os, urllib.request, ssl

GH_TOKEN = os.environ['GH_TOKEN']
REPO = "home-assistant-cn/supervisor"

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
# 显式禁用代理，避免 DevSidecar 干扰
proxy_handler = urllib.request.ProxyHandler({})
https_handler = urllib.request.HTTPSHandler(context=ctx)
opener = urllib.request.build_opener(proxy_handler, https_handler)

headers = {
    'Authorization': f'token {GH_TOKEN}',
    'Accept': 'application/vnd.github+json',
    'Content-Type': 'application/json',
    'User-Agent': 'supervisor-sync-tool',
}

# ============================================================
# 需要更新的变量（3 个）
# ============================================================

# 1. VERSION_SOURCE
#    变更: URL_HASSIO_ADDONS → URL_HASSIO_APPS（官方 addon→app 重命名）
VERSION_SOURCE_NEW = (
    "'s@^URL_HASSIO_APPS =.*@URL_HASSIO_APPS = "
    "\\\"https://gitee.com/smart-assistant/addons\\\"@g; "
    "s@^URL_HASSIO_APPARMOR =.*@URL_HASSIO_APPARMOR = "
    "\\\"https://version.home-assistant.xin/apparmor_{channel}.txt\\\"@g; "
    "s@^URL_HASSIO_VERSION =.*@URL_HASSIO_VERSION = "
    "\\\"https://version.home-assistant.xin/{channel}.json\\\"@g'"
)

# 2. REPLACE_REPOSITORY_NAME
#    变更: 移除 build.yaml 相关替换（文件已删除），仅保留 pyproject.toml 的 URL 替换
REPLACE_REPOSITORY_NAME_NEW = (
    '"s@https://github.com/home-assistant/supervisor@'
    'https://github.com/home-assistant-cn/supervisor@g"'
)

# 3. MODIFY_TIMEZONE
#    变更: 匹配目标从 "Install base" 改为 "Install OS packages"
#          （官方 Dockerfile 重构为多阶段构建，注释已变更）
MODIFY_TIMEZONE_NEW = (
    '"/Install OS packages/i RUN ln -sf /usr/share/zoneinfo/Asia/Shanghai '
    '/etc/localtime\\n\\nRUN echo \\"Asia/Shanghai\\" > /etc/timezone\\n"'
)

# 4. ADDONS_SOURCE（已在之前修复，此处仅验证值是否正确）
ADDONS_SOURCE_EXPECTED = (
    "'s@github.com/hassio-addons/repository@gitee.com/smart-assistant/repository@g; "
    "s@github.com/esphome/home-assistant-addon@gitee.com/smart-assistant/esphome@g; "
    "s@github.com/music-assistant/home-assistant-addon@gitee.com/smart-assistant/music-assistant@g'"
)

variables_to_update = {
    'VERSION_SOURCE': VERSION_SOURCE_NEW,
    'REPLACE_REPOSITORY_NAME': REPLACE_REPOSITORY_NAME_NEW,
    'MODIFY_TIMEZONE': MODIFY_TIMEZONE_NEW,
}

variables_to_verify = {
    'ADDONS_SOURCE': ADDONS_SOURCE_EXPECTED,
}

def api_request(method, path, data=None):
    url = f'https://api.github.com/repos/{REPO}/actions/variables/{path}'
    payload = json.dumps(data).encode('utf-8') if data else None
    req = urllib.request.Request(url, data=payload, method=method, headers=headers)
    try:
        with opener.open(req, timeout=30) as resp:
            body = resp.read().decode()
            return resp.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())

# --- 更新变量 ---
print("\n--- 更新变量 ---")
for name, value in variables_to_update.items():
    status, resp = api_request('PATCH', name, {'name': name, 'value': value})
    if status == 204:
        print(f'  ✅ {name} 更新成功')
    else:
        print(f'  ❌ {name} 更新失败 (HTTP {status}): {resp}')

# --- 验证变量 ---
print("\n--- 验证变量 ---")
for name, expected in variables_to_verify.items():
    status, resp = api_request('GET', name)
    if status == 200 and resp.get('value') == expected:
        print(f'  ✅ {name} 值正确（无需更新）')
    elif status == 200:
        print(f'  ⚠️ {name} 值与预期不符，可能需要手动检查')
        print(f'     当前值: {resp.get("value", "")[:80]}...')
    else:
        print(f'  ❌ {name} 查询失败 (HTTP {status})')

# --- 列出所有变量 ---
print("\n--- 当前所有变量 ---")
req = urllib.request.Request(
    f'https://api.github.com/repos/{REPO}/actions/variables?per_page=100',
    headers=headers
)
with opener.open(req, timeout=30) as resp:
    data = json.loads(resp.read().decode())
    for var in data.get('variables', []):
        print(f'  {var["name"]}: {var["value"][:70]}...')
PYEOF
}

# ===========================================================================
# 阶段 4：验证检查清单
# ===========================================================================
phase4_verify() {
    header "阶段 4：验证检查清单"

    cd "$PROJECT_DIR"

    blue ">> 4.1 检查 sed 匹配目标是否存在"
    echo ""

    declare -A checks=(
        ["VERSION_SOURCE:URL_HASSIO_APPS"]="supervisor/const.py"
        ["VERSION_SOURCE:URL_HASSIO_APPARMOR"]="supervisor/const.py"
        ["VERSION_SOURCE:URL_HASSIO_VERSION"]="supervisor/const.py"
        ["ADDONS_SOURCE:github.com/hassio-addons/repository"]="supervisor/store/const.py"
        ["ADDONS_SOURCE:github.com/esphome/home-assistant-addon"]="supervisor/store/const.py"
        ["ADDONS_SOURCE:github.com/music-assistant/home-assistant-addon"]="supervisor/store/const.py"
        ["REPLACE_REPOSITORY_NAME:github.com/home-assistant/supervisor"]="pyproject.toml"
        ["OS_DOWNLOAD_SOURCE:from .data_disk import DataDisk"]="supervisor/os/manager.py"
        ["OS_DOWNLOAD_SOURCE:raw_url = self.sys_updater.ota_url"]="supervisor/os/manager.py"
        ["GHCR_DOWNLOAD_SOURCE:Downloading docker image %s with tag %s"]="supervisor/docker/interface.py"
        ["SENTRY_SOURCE:o427061.ingest.sentry.io/5370612"]="supervisor/utils/sentry.py"
        ["MODIFY_TIMEZONE:Install OS packages"]="Dockerfile"
    )

    local all_ok=true
    for key in "${!checks[@]}"; do
        local var="${key%%:*}"
        local pattern="${key#*:}"
        local file="${checks[$key]}"
        if [ -f "$file" ] && grep -qF "$pattern" "$file"; then
            green "  ✅ [${var}] ${pattern} → ${file}"
        else
            red "  ❌ [${var}] ${pattern} → ${file} (未找到!)"
            all_ok=false
        fi
    done

    echo ""
    blue ">> 4.2 检查 build.yaml 是否已删除"
    if [ -f "build.yaml" ]; then
        yellow "  ⚠️ build.yaml 仍存在（官方已删除，考虑是否保留）"
    else
        green "  ✅ build.yaml 已删除"
    fi

    echo ""
    blue ">> 4.3 检查 builder.yml sed 命令"
    local builder_yml=".github/workflows/builder.yml"
    if grep -q 'build.yaml' "$builder_yml" 2>/dev/null; then
        red "  ❌ builder.yml 中仍引用 build.yaml"
        grep -n 'build.yaml' "$builder_yml"
        all_ok=false
    else
        green "  ✅ builder.yml 中无 build.yaml 引用"
    fi

    echo ""
    blue ">> 4.4 检查 git 状态"
    git status --short

    echo ""
    if [ "$all_ok" = true ]; then
        green ">> ✅ 所有验证通过！"
    else
        red ">> ❌ 部分验证失败，请检查上方标记为 ❌ 的项"
    fi

    echo ""
    blue ">> 4.5 下一步建议"
    echo "  1. 在 ${BRANCH_NAME} 分支上触发 GitHub Actions 测试构建"
    echo "  2. 验证构建产物中的源替换是否正确"
    echo "  3. 测试通过后合并到 main 分支"
    echo "  4. 合并后再执行阶段 3 更新 GitHub 仓库变量"
    echo ""
    echo "  触发测试构建："
    echo "    git push origin ${BRANCH_NAME}"
    echo ""
    echo "  合并到 main："
    echo "    git checkout main"
    echo "    git merge ${BRANCH_NAME}"
    echo "    git push origin main"
}

# ===========================================================================
# 主入口
# ===========================================================================
main() {
    local phase="${1:-all}"

    case "$phase" in
        --phase\ *)
            phase="${phase#--phase }"
            ;;
    esac

    # 解析 --phase 参数
    if [[ "$1" == "--phase" ]]; then
        phase="$2"
    fi

    green "Supervisor 国内版同步工具"
    green "目标版本: ${TARGET_TAG}"
    green "分支名称: ${BRANCH_NAME}"
    green "项目目录: ${PROJECT_DIR}"
    echo ""

    case "$phase" in
        1)   phase1_sync ;;
        2)   phase2_fix_builder ;;
        3)   phase3_update_vars ;;
        4)   phase4_verify ;;
        all)
            phase1_sync
            echo ""
            yellow ">> 阶段 1 完成。如果合并成功且无冲突，请继续："
            yellow ">>    bash script/sync-upstream.sh --phase 2"
            yellow ">> 如果有冲突，请先解决冲突并提交，再继续。"
            ;;
        *)
            red "未知阶段: ${phase}"
            echo "用法: bash script/sync-upstream.sh [--phase 1|2|3|4|all]"
            exit 1
            ;;
    esac
}

main "$@"
