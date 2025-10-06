#!/bin/bash

# =====================================================
# Antlia MaiBot 自动部署脚本 
# =====================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$SCRIPT_DIR/MaiBot"
LOG_FILE="$SCRIPT_DIR/script.log"

# 输出函数
info() { echo -e "[INFO] $1"; }
ok() { echo -e "[OK]   $1"; }
warn() { echo -e "[WARN] $1"; }
err() { echo -e "[ERR]  $1"; }

# 检查命令
command_exists() { command -v "$1" >/dev/null 2>&1; }

# 检测系统架构
detect_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) MINICONDA_ARCH="x86_64" ;;
        aarch64|arm64) MINICONDA_ARCH="aarch64" ;;
        *) err "不支持架构: $ARCH"; exit 1 ;;
    esac
    ok "检测到系统架构: $ARCH"
}

# 检测包管理器
detect_package_manager() {
    if command_exists apt; then PACKAGE_MANAGER="apt"; ok "检测到 apt"; 
    elif command_exists yum; then PACKAGE_MANAGER="yum"; ok "检测到 yum"; 
    elif command_exists dnf; then PACKAGE_MANAGER="dnf"; ok "检测到 dnf"; 
    elif command_exists pacman; then PACKAGE_MANAGER="pacman"; ok "检测到 pacman"; 
    else err "无法检测支持的包管理器"; exit 1; fi
}

# 安装系统依赖
install_system_dependencies() {
    info "安装系统依赖"
    case $PACKAGE_MANAGER in
        apt) sudo apt update -y && sudo apt install -y redis tmux zip git build-essential g++ ;;
        yum|dnf) sudo $PACKAGE_MANAGER install -y redis tmux zip git gcc gcc-c++ make ;;
        pacman) sudo pacman -Sy --noconfirm redis tmux zip git base-devel gcc ;;
    esac
    ok "系统依赖安装完成"
}

# 安装 Miniconda / Micromamba
install_conda() {
    if command_exists conda; then
        ok "检测到 conda"
        return
    fi
    info "未检测到 conda，安装 micromamba"
    mkdir -p "$HOME/micromamba"
    cd "$HOME"
    curl -Ls "https://micro.mamba.pm/api/micromamba/linux-${MINICONDA_ARCH}/latest" | tar -xvj bin/micromamba >/dev/null 2>&1
    export PATH="$HOME/bin:$PATH"
    alias conda=micromamba
    ok "micromamba 安装完成"
}

# 创建 Python 虚拟环境
create_python_env() {
    info "创建 Python 虚拟环境 MaiBot"
    conda create -n MaiBot python=3.11 -y
    eval "$(conda shell.bash hook)"
    conda activate MaiBot
    ok "虚拟环境已激活"
}

# 克隆 MaiBot 仓库
clone_maibot() {
    info "开始克隆 MaiBot 仓库"
    mkdir -p "$DEPLOY_DIR"
    cd "$DEPLOY_DIR"
    if [ ! -d "$DEPLOY_DIR/MaiBot" ]; then
        git clone --depth 1 "https://github.akams.cn/https://github.com/MaiM-with-u/MaiBot.git" MaiBot || { err "MaiBot 克隆失败"; exit 1; }
    else
        warn "MaiBot 已存在，跳过克隆"
    fi
    if [ ! -d "$DEPLOY_DIR/MaiBot-Napcat-Adapter" ]; then
        git clone --depth 1 "https://github.akams.cn/https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git" MaiBot-Napcat-Adapter || { err "MaiBot-Napcat-Adapter 克隆失败"; exit 1; }
    else
        warn "MaiBot-Napcat-Adapter 已存在，跳过克隆"
    fi
    ok "MaiBot 仓库克隆完成"
}

# 安装 Python 依赖
install_python_dependencies() {
    info "安装 Python 依赖"
    for d in MaiBot MaiBot-Napcat-Adapter; do
        if [ -f "$DEPLOY_DIR/$d/requirements.txt" ]; then
            pip install -r "$DEPLOY_DIR/$d/requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple
        else
            warn "$d/requirements.txt 不存在，跳过"
        fi
    done
    ok "Python 依赖安装完成"
}

# 下载 Lagrange
install_lagrange() {
    info "安装 Lagrange"
    mkdir -p "$DEPLOY_DIR/Lagrange"
    cd "$DEPLOY_DIR/Lagrange"
    if [ "$MINICONDA_ARCH" = "x86_64" ]; then
        wget -O Lagrange.OneBot https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/Lagrange.OneBot/Lagrange.OneBot
    else
        wget -O Lagrange.OneBot https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/Lagrange.OneBot/Lagrange.OneBot-arm64
    fi
    chmod +x Lagrange.OneBot
    wget -O appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-MaiBot.json
    ok "Lagrange 安装完成"
}

# 安装 Napcat
install_napcat() {
    info "安装 Napcat"
    cd "$DEPLOY_DIR"
    curl -L -o NapCat.Shell.zip https://github.akams.cn/https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip
    if [ ! -f NapCat.Shell.zip ]; then err "NapCat.Shell.zip 下载失败"; exit 1; fi
    ok "Napcat 下载完成"
}

# 主函数
main() {
    clear
    info "Antlia MaiBot 自动部署脚本"

    detect_architecture
    detect_package_manager
    install_system_dependencies
    install_conda
    create_python_env
    clone_maibot
    install_python_dependencies

    info "选择部署组件"
    echo "1. Lagrange"
    echo "2. NapcatQQ"
    echo "3. 全部"
    read -p "请选择 (默认3): " choice
    choice=${choice:-3}
    case $choice in
        1) install_lagrange ;;
        2) install_napcat ;;
        3) install_lagrange; install_napcat ;;
        *) warn "无效选择，跳过组件安装" ;;
    esac

    ok "部署完成！请进入 $DEPLOY_DIR/MaiBot 并使用 maibot.sh 启动"
}

main