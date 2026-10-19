#!/usr/bin/env bash
# niri-better：用本仓库编译好的 niri 替换当前系统里的 niri，并能随时退回原版。
#
#   bash install.sh                  从 GitHub Release 下载最新版并安装
#   bash install.sh install --local niri-xxx.tar.gz   用本地的包或自己编译的 niri
#
# 安装后可以用 niri-better 命令管理：status / off / on / once / uninstall。
#
# 不覆盖发行版包管理器装的任何文件：新版装在 /usr/local，再用 systemd drop-in
# 让 niri.service 改用它。发行版升级 niri 不会冲掉它，卸载时删掉这几个文件即可还原。

set -euo pipefail

REPO=zelin652-creator/niri-better-action
LIB=/usr/local/lib/niri-better
WRAPPER=/usr/local/bin/niri
SELF_CMD=/usr/local/bin/niri-better
DROPIN_DIR=/etc/systemd/user/niri.service.d
DROPIN=$DROPIN_DIR/50-niri-better.conf
SESSION_FILE=/usr/local/share/wayland-sessions/niri-original.desktop
# 固定路径，不跟随 XDG_STATE_HOME：登录界面和 systemd 服务里这个变量可能不一致。
STATE=$HOME/.local/state/niri-better

if [ -t 1 ]; then
    B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'
else
    B='' G='' Y='' R='' N=''
fi
info() { printf '%s==>%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s警告：%s%s\n' "$Y" "$*" "$N" >&2; }
die() {
    printf '%s错误：%s%s\n' "$R" "$*" "$N" >&2
    exit 1
}

usage() {
    cat <<EOF
用法：niri-better <命令> [选项]

  install [--local 文件] [--version 标签] [--force] [--yes]
            安装或更新。默认下载最新 Release；--local 可以是 Release 的 .tar.gz，
            也可以是自己编译的 target/release/niri。
  status    查看当前状态
  off       以后登录都用原版 niri（新版保留，随时可 on）
  on        切回新版 niri，并清零启动失败计数
  once      只有下一次登录用原版
  uninstall 完全还原，删除本脚本装的所有文件

兜底：新版连续 2 次没能正常启动，下次登录会自动改用原版。
图形界面进不去时，按 Ctrl+Alt+F3 进入终端登录，运行 niri-better off 或 niri-better uninstall。
EOF
}

need_sudo() {
    command -v sudo >/dev/null 2>&1 || die "需要 sudo 来写入 /usr/local 和 /etc"
    sudo -v || die "sudo 验证失败"
}

has_niri_unit() {
    systemctl --user cat niri.service >/dev/null 2>&1 && return 0
    local d
    for d in /etc/systemd/user /usr/lib/systemd/user /usr/local/lib/systemd/user /lib/systemd/user; do
        [ -f "$d/niri.service" ] && return 0
    done
    return 1
}

user_daemon_reload() {
    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# 原版 niri 由哪个包提供，只用于显示。
package_owner() {
    local f=$1
    if command -v pacman >/dev/null 2>&1; then
        pacman -Qoq "$f" 2>/dev/null && return
    fi
    if command -v dpkg >/dev/null 2>&1; then
        dpkg -S "$f" 2>/dev/null | cut -d: -f1 && return
    fi
    if command -v rpm >/dev/null 2>&1; then
        rpm -qf "$f" 2>/dev/null && return
    fi
    echo "（不属于任何软件包）"
}

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        die "需要 curl 或 wget 来下载"
    fi
}

write_wrapper() {
    # 安装后 /usr/local/bin/niri 是这个小脚本。以会话方式启动（--session）时做启动保护，
    # 其余用法（niri msg、niri validate……）直接交给新版。
    cat <<'EOF'
#!/bin/sh
# 由 niri-better 安装，卸载请运行 niri-better uninstall。
LIB=/usr/local/lib/niri-better
REAL=$LIB/niri
ORIGINAL=$(cat "$LIB/original" 2>/dev/null)
STATE=$HOME/.local/state/niri-better
MAX_FAILED=2

log() { echo "niri-better: $*" >&2; }

run_original() {
    if [ -n "$ORIGINAL" ] && [ -x "$ORIGINAL" ]; then
        exec "$ORIGINAL" "$@"
    fi
    log "找不到原版 niri（$ORIGINAL），仍使用新版"
    exec "$REAL" "$@"
}

[ -x "$REAL" ] || run_original "$@"

session=false
for arg in "$@"; do
    [ "$arg" = --session ] && session=true
done
$session || exec "$REAL" "$@"

mkdir -p "$STATE" 2>/dev/null

if [ -e "$STATE/use-original-once" ]; then
    rm -f "$STATE/use-original-once"
    log "本次登录使用原版 niri"
    run_original "$@"
fi
if [ -e "$STATE/disabled" ]; then
    log "已设为使用原版 niri，运行 niri-better on 可切回新版"
    run_original "$@"
fi

failed=$(cat "$STATE/failed-starts" 2>/dev/null)
case $failed in '' | *[!0-9]*) failed=0 ;; esac
if [ "$failed" -ge "$MAX_FAILED" ]; then
    log "新版 niri 连续 $failed 次没能正常启动，已自动改用原版；修好后运行 niri-better on"
    echo auto > "$STATE/disabled"
    rm -f "$STATE/failed-starts"
    run_original "$@"
fi

# 先记一次失败，运行满 30 秒再清零。exec 之后 $$ 就是 niri 进程本身。
echo $((failed + 1)) > "$STATE/failed-starts"
(sleep 30; kill -0 $$ 2>/dev/null && rm -f "$STATE/failed-starts") </dev/null >/dev/null 2>&1 &
exec "$REAL" "$@"
EOF
}

write_dropin() {
    cat <<EOF
# 由 niri-better 安装，让 niri.service 经过 $WRAPPER 启动。
[Service]
ExecStart=
ExecStart=$WRAPPER --session
EOF
}

write_session_file() {
    cat <<EOF
[Desktop Entry]
Name=Niri（原版）
Comment=只在这一次登录使用原版 niri，由 niri-better 安装
Exec=$SELF_CMD session-original
Type=Application
DesktopNames=niri
EOF
}

# 找出要被替换的原版 niri 的路径。
detect_original() {
    if [ -f "$LIB/original" ]; then
        ORIGINAL=$(cat "$LIB/original")
        UPDATING=true
        return
    fi
    UPDATING=false

    local p
    p=$(command -v niri 2>/dev/null || true)
    if [ "$p" = "$WRAPPER" ] && grep -q niri-better "$WRAPPER" 2>/dev/null; then
        # 上次装到一半：包装脚本在，记录丢了。
        p=""
        for c in /usr/bin/niri /bin/niri; do
            [ -x "$c" ] && p=$c && break
        done
    fi
    [ -n "$p" ] || die "没有找到已安装的 niri。请先用发行版的包管理器装好 niri（它会带上登录会话、门户配置等文件），再运行本脚本。"
    ORIGINAL=$(readlink -f "$p")
}

get_package() {
    local tmp=$1 local_file=$2 tag=$3

    if [ -n "$local_file" ]; then
        [ -f "$local_file" ] || die "找不到文件 $local_file"
        case $local_file in
        *.tar.gz | *.tgz)
            tar -xzf "$local_file" -C "$tmp" || die "解压失败：$local_file"
            NEW=$tmp/usr/bin/niri
            ;;
        *)
            NEW=$tmp/niri
            cp "$local_file" "$NEW"
            chmod +x "$NEW"
            ;;
        esac
        [ -x "$NEW" ] || die "$local_file 里没有 usr/bin/niri"
        NEW_TAG=local
        return
    fi

    [ "$(uname -m)" = x86_64 ] ||
        die "Release 只提供 x86_64 版本，这台机器是 $(uname -m)。请自己编译后用 --local target/release/niri 安装。"

    if [ -z "$tag" ]; then
        info "查询最新版本"
        fetch "https://api.github.com/repos/$REPO/releases/latest" "$tmp/latest.json" ||
            die "查询失败。Release 可能还没发布，或者网络连不上 GitHub。"
        tag=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$tmp/latest.json" | head -n1)
        [ -n "$tag" ] || die "没有找到已发布的 Release"
    fi
    local name="niri-${tag#v}-x86_64-linux.tar.gz"
    local url="https://github.com/$REPO/releases/download/$tag/$name"

    info "下载 $tag"
    fetch "$url" "$tmp/$name" || die "下载失败：$url"
    if fetch "$url.sha256" "$tmp/$name.sha256"; then
        (cd "$tmp" && sha256sum -c --quiet "$name.sha256") || die "校验和不匹配，下载的文件可能已损坏"
    else
        warn "没有找到校验文件，跳过校验"
    fi
    tar -xzf "$tmp/$name" -C "$tmp" || die "解压失败"
    NEW=$tmp/usr/bin/niri
    [ -x "$NEW" ] || die "包里没有 usr/bin/niri"
    NEW_TAG=$tag
}

# 装之前先确认新版能在这台机器上跑，并且能读懂现在的配置。
check_new_binary() {
    local force=$1

    if ! NEW_VERSION=$("$NEW" --version 2>&1); then
        echo "$NEW_VERSION" >&2
        local missing=""
        if command -v ldd >/dev/null 2>&1; then
            missing=$(ldd "$NEW" 2>/dev/null | awk '/not found/ {print $1}' | tr '\n' ' ')
        fi
        if [ -n "$missing" ]; then
            die "系统缺少新版 niri 需要的库：$missing
如果原版 niri 能正常用，说明发行版里这个库的版本和编译环境不同。请先运行 bash install.sh 换最新的 Release 再试；仍不行就自己编译后用 --local target/release/niri 安装（见 README）。"
        fi
        case $NEW_VERSION in
        *GLIBC_*) die "系统的 glibc 太旧，新版需要 2.39 以上。请自己编译后用 --local target/release/niri 安装（见 README）。" ;;
        esac
        die "新版 niri 在这台机器上运行不了（见上面的输出）。可以自己编译后用 --local target/release/niri 安装（见 README）。"
    fi
    info "新版：$NEW_VERSION"

    local cfg=${NIRI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl}
    if [ -f "$cfg" ]; then
        if "$NEW" validate -c "$cfg" >/dev/null 2>&1; then
            info "配置检查通过：$cfg"
        else
            "$NEW" validate -c "$cfg" || true
            if [ "$force" = true ]; then
                warn "新版读不懂你现在的配置，按 --force 继续安装"
            else
                die "新版读不懂你现在的配置（见上面的错误）。原版可能比本仓库的基线 v26.04 更新，用到了新选项。改好配置或加 --force 再试。"
            fi
        fi
    fi
}

install_self() {
    local src=${BASH_SOURCE[0]:-}
    if [ -n "$src" ] && [ -f "$src" ] && grep -q 'niri-better' "$src"; then
        [ "$(readlink -f "$src")" = "$SELF_CMD" ] && return
        sudo install -m755 "$src" "$SELF_CMD"
    else
        # 通过管道运行（curl ... | bash）时没有脚本文件，从仓库下载一份。
        local tmp
        tmp=$(mktemp)
        fetch "https://raw.githubusercontent.com/$REPO/main/install.sh" "$tmp" ||
            die "下载 niri-better 管理脚本失败"
        sudo install -m755 "$tmp" "$SELF_CMD"
        rm -f "$tmp"
    fi
}

cmd_install() {
    local local_file="" tag="" force=false yes=false
    while [ $# -gt 0 ]; do
        case $1 in
        --local)
            [ $# -ge 2 ] || die "--local 后面要跟一个文件"
            local_file=$(readlink -f "$2")
            shift
            ;;
        --version)
            [ $# -ge 2 ] || die "--version 后面要跟一个标签，例如 v26.04-better.1"
            tag=$2
            shift
            ;;
        --force) force=true ;;
        -y | --yes) yes=true ;;
        -h | --help) usage; exit 0 ;;
        *) die "未知选项：$1" ;;
        esac
        shift
    done

    [ "$(id -u)" -ne 0 ] || die "请用普通用户运行，需要时脚本会自己调用 sudo（要检查的是你自己的 niri 配置）"
    [ "$(uname -s)" = Linux ] || die "只支持 Linux"
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        [ "${ID:-}" != nixos ] || die "NixOS 的 /usr 由系统配置管理，请改用仓库里的 flake.nix 在配置中替换 niri。"
        info "系统：${PRETTY_NAME:-$ID}"
    fi
    for c in tar sha256sum install readlink; do
        command -v "$c" >/dev/null 2>&1 || die "缺少命令：$c"
    done

    detect_original
    if [ "$UPDATING" = true ]; then
        info "已安装过 niri-better，这次是更新。原版：$ORIGINAL"
    else
        info "原版 niri：$ORIGINAL，来自 $(package_owner "$ORIGINAL")"
        info "原版版本：$("$ORIGINAL" --version 2>&1 || echo 未知)"
    fi

    tmp=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
    get_package "$tmp" "$local_file" "$tag"
    check_new_binary "$force"

    local unit=false
    has_niri_unit && unit=true

    echo
    echo "${B}将要做的事：${N}"
    echo "  - 新版 niri 装到 $LIB/niri，$WRAPPER 换成带启动保护的包装脚本"
    [ "$unit" = true ] && echo "  - 添加 $DROPIN，让 niri.service 改用新版"
    [ "$UPDATING" = false ] && [ "$ORIGINAL" = "$WRAPPER" ] &&
        echo "  - 你原来的 $WRAPPER 移到 $LIB/backup/niri，卸载时放回"
    echo "  - 登录界面增加「Niri（原版）」，选它就只这一次用原版"
    echo "  - 安装管理命令 $SELF_CMD"
    echo "  原版 niri 本身不会被修改或删除。"
    echo
    if [ "$yes" = false ]; then
        if [ -t 0 ]; then
            read -r -p "继续吗？[y/N] " ans
        else
            read -r -p "继续吗？[y/N] " ans </dev/tty || ans=n
        fi
        case $ans in y | Y | yes) ;; *) die "已取消" ;; esac
    fi

    need_sudo
    sudo install -d "$LIB"

    if [ "$UPDATING" = false ] && [ "$ORIGINAL" = "$WRAPPER" ]; then
        sudo install -d "$LIB/backup"
        sudo mv "$WRAPPER" "$LIB/backup/niri"
        ORIGINAL=$LIB/backup/niri
    fi
    if [ "$UPDATING" = true ] && [ -x "$LIB/niri" ]; then
        sudo cp -f "$LIB/niri" "$LIB/niri.prev"
    fi

    # 先写到临时名再改名，正在运行的 niri 不受影响。
    sudo install -m755 "$NEW" "$LIB/niri.new"
    sudo mv -f "$LIB/niri.new" "$LIB/niri"
    echo "$ORIGINAL" | sudo tee "$LIB/original" >/dev/null
    printf '%s\n%s\n' "$NEW_TAG" "$NEW_VERSION" | sudo tee "$LIB/version" >/dev/null

    write_wrapper >"$tmp/wrapper"
    sudo install -m755 "$tmp/wrapper" "$WRAPPER"

    if [ "$unit" = true ]; then
        write_dropin >"$tmp/dropin"
        sudo install -d "$DROPIN_DIR"
        sudo install -m644 "$tmp/dropin" "$DROPIN"
        user_daemon_reload
    fi

    write_session_file >"$tmp/session"
    sudo install -Dm644 "$tmp/session" "$SESSION_FILE"

    install_self

    rm -f "$STATE/failed-starts" "$STATE/disabled" "$STATE/use-original-once"

    "$WRAPPER" --version >/dev/null 2>&1 || die "安装后的 niri 无法运行，请运行 niri-better uninstall 还原"

    echo
    info "${B}安装完成。${N}注销后重新登录即可使用新版。"
    [ -n "${NIRI_SOCKET:-}" ] && echo "  当前正在运行的会话不受影响。"
    if [ "$unit" = false ]; then
        warn "没有找到 niri.service。如果你不是通过 niri-session 或 niri --session 启动 niri，请确认启动命令用的是 $WRAPPER"
    fi
    cat <<EOF

出问题时：
  - 新版连续 2 次没能正常启动，下次登录自动改用原版
  - 登录界面选「Niri（原版）」，只这一次用原版
  - niri-better off       以后都用原版（niri-better on 切回）
  - niri-better uninstall 完全还原
  - 图形界面进不去：Ctrl+Alt+F3 进入终端登录，再运行上面的命令
EOF
}

require_installed() {
    [ -f "$LIB/original" ] || die "还没有安装 niri-better"
}

cmd_status() {
    if [ ! -f "$LIB/original" ]; then
        echo "未安装。系统当前的 niri：$(command -v niri || echo 无)"
        return
    fi
    local orig mode="新版"
    orig=$(cat "$LIB/original")
    [ -e "$STATE/use-original-once" ] && mode="下次登录用原版，之后回到新版"
    if [ -e "$STATE/disabled" ]; then
        mode="原版（niri-better on 切回新版）"
        [ "$(cat "$STATE/disabled" 2>/dev/null)" = auto ] && mode="原版（新版连续启动失败，已自动切换）"
    fi
    echo "${B}新版：${N}    $(sed -n 2p "$LIB/version" 2>/dev/null)（$(sed -n 1p "$LIB/version" 2>/dev/null)）"
    echo "${B}原版：${N}    $orig  $("$orig" --version 2>/dev/null || echo '（不存在）')"
    echo "${B}登录时用：${N}$mode"
    echo "${B}启动失败：${N}$(cat "$STATE/failed-starts" 2>/dev/null || echo 0) 次（满 2 次自动改用原版）"
    if [ -f "$DROPIN" ]; then
        echo "${B}systemd：${N} 已覆盖 niri.service（$DROPIN）"
    fi
    if [ -n "${NIRI_SOCKET:-}" ]; then
        echo "${B}正在运行：${N}$(niri msg version 2>/dev/null | grep -i compositor || echo 未知)"
    fi
}

cmd_off() {
    require_installed
    mkdir -p "$STATE"
    echo manual >"$STATE/disabled"
    info "以后登录都用原版 niri。运行 niri-better on 可切回新版。"
}

cmd_on() {
    require_installed
    rm -f "$STATE/disabled" "$STATE/failed-starts" "$STATE/use-original-once"
    info "以后登录用新版 niri。"
}

cmd_once() {
    require_installed
    mkdir -p "$STATE"
    : >"$STATE/use-original-once"
    info "下一次登录用原版 niri，之后回到新版。"
}

# 登录界面的「Niri（原版）」会话调用这个。
cmd_session_original() {
    mkdir -p "$STATE"
    : >"$STATE/use-original-once"
    if command -v niri-session >/dev/null 2>&1; then
        exec niri-session "$@"
    fi
    exec "$(cat "$LIB/original")" --session
}

cmd_uninstall() {
    require_installed
    need_sudo
    info "还原原版 niri"
    sudo rm -f "$DROPIN"
    sudo rmdir "$DROPIN_DIR" 2>/dev/null || true
    sudo rm -f "$WRAPPER" "$SESSION_FILE"
    if [ -x "$LIB/backup/niri" ]; then
        sudo mv "$LIB/backup/niri" "$WRAPPER"
    fi
    sudo rm -rf "$LIB"
    user_daemon_reload
    rm -rf "$STATE"
    sudo rm -f "$SELF_CMD"
    info "已还原，现在的 niri：$(command -v niri || echo 无)。注销后重新登录生效。"
}

main() {
    local cmd=${1:-install}
    [ $# -gt 0 ] && shift
    case $cmd in
    install) cmd_install "$@" ;;
    --local | --version | --force | -y | --yes) cmd_install "$cmd" "$@" ;;
    status) cmd_status ;;
    off) cmd_off ;;
    on) cmd_on ;;
    once) cmd_once ;;
    uninstall) cmd_uninstall ;;
    session-original) cmd_session_original "$@" ;;
    -h | --help | help) usage ;;
    *) usage >&2; exit 1 ;;
    esac
}

main "$@"
