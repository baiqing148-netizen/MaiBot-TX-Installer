pkg install wget -y > /dev/null 2>&1
pkg install curl -y > /dev/null 2>&1
#!/bin/bash

# 获取脚本绝对路径
#set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # 获取脚本所在目录
DEPLOY_DIR="$SCRIPT_DIR/MaiBot" # 部署目录
LOG_FILE="$SCRIPT_DIR/script.log" #  日志文件路径
DEPLOY_STATUS_FILE="$SCRIPT_DIR/MaiBot/deploy.status" # 部署状态文件


# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1 # 检查命令是否存在
}

# 输出函数
info() { echo "> $1"; } # 信息输出函数
ok() { echo "[OK] $1"; } # 成功输出函数
warn() { echo "[!] $1"; } # 警告输出函数
err() { echo "[X] $1"; } # 错误输出函数
# 标题输出函数
print_title() {
    echo
    echo "$1"
    echo
}
# 兼容print_success
print_success() {
    ok "$1"
}
# 检测系统架构
detect_architecture() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            MINICONDA_ARCH="x86_64"
            ;;
        aarch64|arm64)
            MINICONDA_ARCH="aarch64"
            ;;
        *)
            err "不支持的架构: $ARCH"
            warn "请手动安装 Miniconda 并重新运行脚本"
            exit 1
            ;;
    esac
    ok "检测到系统架构: $ARCH (Linux架构: $MINICONDA_ARCH)"
}

# 确定 Linux 发行版和包管理器
detect_package_manager() {
    info "检测系统包管理器"
    if command_exists apt; then
        PACKAGE_MANAGER="apt"
        ok "检测到 Debian/Ubuntu 系统 (apt)"
    elif command_exists yum; then
        PACKAGE_MANAGER="yum"
        ok "检测到 Red Hat/CentOS 系统 (yum)"
    elif command_exists dnf; then
        PACKAGE_MANAGER="dnf"
        ok "检测到 Fedora 系统 (dnf)"
    elif command_exists pacman; then
        PACKAGE_MANAGER="pacman"
        ok "检测到 Arch Linux 系统 (pacman)"
    else
        err "无法检测到支持的包管理器"
        exit 1
    fi
}

install_system_dependencies() {
    info "安装系统依赖"
    case $PACKAGE_MANAGER in
        apt)
            sudo apt update > /dev/null 2>&1
            sudo apt install -y redis tmux zip git build-essential g++
            ;;
        yum|dnf)
            sudo $PACKAGE_MANAGER install -y tmux zip redis git gcc gcc-c++ make
            ;;
        pacman)
            sudo pacman -Sy --noconfirm redis tmux zip git base-devel gcc
            ;;
    esac
}




# 检查并激活conda环境（如已安装）
check_and_activate_conda() {
    local conda_dir=""
    if [ -d "$HOME/miniconda3" ] && [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        conda_dir="$HOME/miniconda3"
    elif [ -d "$HOME/miniconda" ] && [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
        conda_dir="$HOME/miniconda"
    fi
    if [ -n "$conda_dir" ]; then
        info "检测到已安装的conda环境: $conda_dir"
        source "$conda_dir/etc/profile.d/conda.sh"
        return 0
    else
        warn "未检测到conda环境，将自动安装Miniconda"
        return 1
    fi
}

# 创建Python虚拟环境（单独函数）
create_python_env() {
    info "创建 Python 虚拟环境 (Eridanus)"
    conda create -n MaiBot python=3.11 -y || { err "虚拟环境创建失败"; exit 1; }
    conda activate MaiBot  # 激活新环境
    ok "虚拟环境已创建并激活"
    cd "$DEPLOY_DIR"  # 切回部署目录
}








# 安装和配置 Conda 环境
install_conda_environment() {
    # 1. 创建Miniconda安装目录
    info "创建安装目录"
    CONDA_DIR="$HOME/miniconda3"  # Miniconda安装路径
    mkdir -p "$CONDA_DIR"  # 创建目录

    cd "$SCRIPT_DIR"  # 切换到脚本目录
    # 2. 检查是否已有安装包
    if [ -f "miniconda.sh" ]; then
        ok "发现 miniconda.sh 文件，直接使用"
    else
        info "尝试从清华源下载Miniconda安装脚本"
        # 优先清华源，失败则官方源
        if wget https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-$MINICONDA_ARCH.sh -O miniconda.sh; then
            ok "已从清华源下载Miniconda安装脚本"
        else
            warn "清华源下载失败，尝试官方源"
            if wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-$MINICONDA_ARCH.sh -O miniconda.sh; then
                ok "已从官方源下载Miniconda安装脚本"
            else
                err "Miniconda安装脚本下载失败，请检查网络或手动下载"
                exit 1
            fi
        fi
    fi

    # 3. 运行安装脚本（-b无交互，-u覆盖，-p指定路径）
    info "运行安装脚本（无交互模式）"
    bash miniconda.sh -b -u -p "$CONDA_DIR" || { err "Miniconda 安装失败"; exit 1; }

    # 4. 清理安装包
    info "清理安装文件"
    rm -f miniconda.sh

    # 5. 激活conda环境变量
    info "激活conda环境"
    source "$CONDA_DIR/etc/profile.d/conda.sh"
    # 6. 初始化conda（写入shell配置）
    info "初始化conda"
    conda init --all || { err "conda init 失败"; exit 1; }
    # 7. 重新加载bash配置
    info "激活bash配置"
    source ~/.bashrc

    # 8. 验证conda安装
    info "验证安装"
    if conda --version; then
        ok "Miniconda安装成功！"
        info "安装路径: $CONDA_DIR"
        info "运行 conda activate 激活基础环境"
    else
        err "Miniconda安装验证失败"
        exit 1
    fi

    # 9. 配置conda镜像和服务条款
    info "配置 Conda 镜像源与服务条款"
    info "如遇网络慢/失败会自动切换USTC/官方源"
    info "接受 Anaconda 条款服务..."
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true  # 接受主源条款
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true  # 接受R源条款

    # 10. 优先使用清华源加速
    info "使用清华源"
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/
    conda config --add channels https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge/


}

# 安装 Python 依赖
install_python_dependencies() {
    info "安装 Python 依赖"
    cd "$DEPLOY_DIR/MaiBot" || exit
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple > /dev/null 2>&1
    pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    mkdir config
    # 复制并重命名配置文件
    cp template/bot_config_template.toml config/bot_config.toml
    cp template/template.env .env
    cd "$DEPLOY_DIR/MaiBot-Napcat-Adapter"
    pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    # 复制并重命名文件
    cp template/template_config.toml config.toml
    ok "Python 依赖已安装"
}



clone_maibot() {
    info "选择 MaiBot 克隆源" # 选择源
    echo "1.  https://github.com/MaiM-with-u/MaiBot.git"
    echo "2.  https://ghproxy.sakuramoe.dev/https://github.com/MaiM-with-u/MaiBot.git"
    echo "3.  https://github.akams.cn/https://github.com/MaiM-with-u/MaiBot.git 默认"
    echo "4.  https://ghproxy.net/https://github.com/MaiM-with-u/MaiBot.git"

    read -t 15 -p "请输入选择 1-4 : " reply # 选择源
    reply=${reply:-3} # 默认选择3

    case $reply in  # 选择源
        1)  
            CLONE_URL="https://github.com/MaiM-with-u/MaiBot.git" # 选择官方源
            CLONE_URL1="https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git"
            ok "1"
            ;;
        2)
            CLONE_URL="https://ghproxy.sakuramoe.dev/https://github.com/MaiM-with-u/MaiBot.git"
            CLONE_URL1="https://ghproxy.sakuramoe.dev/https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git"
            ok "2"
            ;;
        3)
            CLONE_URL="https://github.akams.cn/https://github.com/MaiM-with-u/MaiBot.git"
            CLONE_URL1="https://github.akams.cn/https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git"
            ok "3"
            ;;
        4)
            CLONE_URL="https://ghproxy.net/https://github.com/MaiM-with-u/MaiBot.git"
            CLONE_URL1="https://ghproxy.net/https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git"
            ok "4"
            ;;
        *)
            warn "无效输入，使用默认源"
            CLONE_URL="https://github.akams.cn/https://github.com/MaiM-with-u/MaiBot.git"
            CLONE_URL1="https://github.akams.cn/https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git"
            ;;
    esac # 选择源结束

    if [ -d "$DEPLOY_DIR/MaiBot" ]; then # 如果目录已存在
        warn "检测到MaiBot 文件夹已存在。是否删除重新克隆？(y/n)" # 提示用户是否删除
        read -p "请输入选择 (y/n, 默认n): " del_choice # 询问用户是否删除
        del_choice=${del_choice:-n} # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then # 如果用户选择删除
            rm -rf "$DEPLOY_DIR/MaiBot" # 删除MaiBot目录
            ok "已删除MaiBot 文件夹。" # 提示用户已删除
        else # 如果用户选择不删除
            warn "跳过MaiBot仓库克隆。" # 提示用户跳过克隆
            return # 结束函数
        fi # 结束删除选择
    fi # 如果目录不存在则继续克隆
    info "克隆 MaiBot 仓库" # 提示用户开始克隆
    git clone --depth 1 "$CLONE_URL" # 克隆仓库
    
    if [ -d "$DEPLOY_DIR/MaiBot-Napcat-Adapter" ]; then # 如果目录已存在
        warn "检测到MaiBot-Napcat-Adapter文件夹已存在。是否删除重新克隆？(y/n)" # 提示用户是否删除
        read -p "请输入选择 (y/n, 默认n): " del_choice # 询问用户是否删除
        del_choice=${del_choice:-n} # 默认选择不删除
        if [ "$del_choice" = "y" ] || [ "$del_choice" = "Y" ]; then # 如果用户选择删除
            rm -rf "$DEPLOY_DIR/MaiBot-Napcat-Adapter" # 删除目录
            ok "已删除MaiBot-Napcat-Adapter文件夹。" # 提示用户已删除
        else # 如果用户选择不删除
            warn "跳过MaiBot-Napcat-Adapter仓库克隆。" # 提示用户跳过克隆
            return # 结束函数
        fi # 结束删除选择
    fi # 如果目录不存在则继续克隆
     git clone --depth 1 "$CLONE_URL1" # 克隆仓库
}  # 克隆 仓库结束



# 下载并安装 Lagrange
install_lagrange() {
    mkdir Lagrange
    cd Lagrange
    print_title "安装 Lagrange"
if [ "${MINICONDA_ARCH}" = "x86_64" ]; then
    wget -O Lagrange.OneBot https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/Lagrange.OneBot/Lagrange.OneBot
    chmod +x Lagrange.OneBot
else
    wget -O Lagrange.OneBot https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/Lagrange.OneBot/Lagrange.OneBot-arm64
    chmod +x Lagrange.OneBot
fi
    wget -O appsettings.json https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/Lagrange.OneBot/Lagrange.OneBot-Data/appsettings/appsettings-MaiBot.json
     print_success "Lagrange 安装完成"
     cd ..
}

# 下载并安装 Napcat
install_napcat() {
if [ "${PACKAGE_MANAGER}" = "pacman" ]; then # 如果是 Arch Linux 系统
    info "安装 Napcat"  # 安装 Napcat
    wget -O napcat.sh https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/NapCat/napcat-dpkg.sh && chmod +x napcat.sh && sudo bash napcat.sh # 安装 Napcat
    ok "Napcat 安装完成" # 提示用户已安装
else # 如果是其他系统
    info "安装 Napcat"  # 安装 Napcat
    # 使用 gh-proxy 镜像下载 NapCat.Shell.zip
    # 如果下载失败则提示用户手动安装
    curl -L -o NapCat.Shell.zip https://github.akams.cn/https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip # 下载 NapCat.Shell.zip
    if [ -f NapCat.Shell.zip ]; then # 如果下载成功
        ok "NapCat.Shell.zip 下载完成" # 提示用户下载成功
    else # 如果下载失败
        err "NapCat.Shell.zip 下载失败" # 提示用户下载失败
        exit 1 # 退出脚本
    fi # 结束
    curl -o \
napcat.sh \
https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh \
&& sudo bash napcat.sh \
--docker n \
--cli n  # 安装 Napcat
    ok "Napcat 安装完成" # 提示用户已安装
    ## 安装 Napcat CLI
    #info "安装 Napcat CLI" # 安装 Napcat CLI
    # 使用 gh-proxy 镜像下载 NapCat-TUI-CLI 安装脚本
    # 如果下载失败则提示用户手动安装
    wget -O napcat-cli.sh https://github.akams.cn/https://raw.githubusercontent.com/NapNeko/NapCat-TUI-CLI/refs/heads/main/script/install-cli.sh && chmod +x napcat-cli.sh # && sudo bash napcat-cli.sh # 下载并安装 Napcat CLI
    sudo bash napcat-cli.sh # 安装 Napcat CLI
    ok "Napcat CLI 安装完成" # 提示用户已安装
    ok "Napcat 安装完成" # 提示用户已安装
fi 

}

# 主函数
main() {
    clear
    info "Antlia MaiBot部署脚本 2025/7/29 "

    # 1. 检测系统架构
    detect_architecture
    # 2. 检测包管理器
    detect_package_manager
    # 3. 安装系统依赖
    install_system_dependencies

    info "创建项目目录"
    mkdir -p MaiBot
    cd MaiBot || exit
    ok "项目目录已创建: $(pwd)"

    # 检查conda环境，已安装则激活，否则后续自动安装
    if check_and_activate_conda; then
        info "跳过Miniconda安装，直接创建虚拟环境"
        create_python_env
    else
        install_conda_environment
        create_python_env
    fi

    info "选择要部署的NTQQ实现"
    echo "1. 安装Lagrange"
    echo "2. 安装NapcatQQ"
    echo "3. 我全都要😋"
    read -p "请选择 (1-3, 默认3): " choice
    choice=${choice:-3}
    LAGRANGE_DEPLOYED=0
    NAPCAT_DEPLOYED=0

    case $choice in
        1)
            install_lagrange
            LAGRANGE_DEPLOYED=1
            update_config_file
            ;;
        2)
            install_napcat
            NAPCAT_DEPLOYED=1
            ;;
        3)
            install_lagrange
            install_napcat
            LAGRANGE_DEPLOYED=1
            NAPCAT_DEPLOYED=1
            update_config_file
            ;;
        *)
            warn "无效选择，跳过额外部署"
            ;;
    esac

    # 写入部署状态
    echo "LAGRANGE_DEPLOYED=$LAGRANGE_DEPLOYED" > "$DEPLOY_STATUS_FILE"
    echo "NAPCAT_DEPLOYED=$NAPCAT_DEPLOYED" >> "$DEPLOY_STATUS_FILE"

    # 安装Python依赖
    clone_maibot
    install_python_dependencies
    cd "$SCRIPT_DIR"
    wget -O maibot.sh https://cnb.cool/zhende1113/Antlia/-/git/raw/main/Script/MaiBot/maibot.sh
    chmod +x maibot.sh
    info "部署成功！"
    ok "请运行 bash $(SCRIPT_DIR)/maibot.sh 来启动和管理服务"
}

#主函数
main

