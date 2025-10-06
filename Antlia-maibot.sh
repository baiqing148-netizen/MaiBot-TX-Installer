#!/bin/bash

# 定义颜色输出函数
RED=\'\\033[0;31m\'
GREEN=\'\\033[0;32m\'
YELLOW=\'\\033[0;33m\'
NC=\'\\033[0m\' # No Color

log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

# 检查是否在Termux环境中运行
if [[ -z "$PREFIX" ]]; then
    log_error "此脚本必须在Termux环境中运行。"
fi

log_info "欢迎使用MaiBot Android一键部署脚本！"
log_info "本脚本将引导您在Termux中安装Ubuntu，并在Ubuntu环境中部署MaiBot和Napcat Adapter。"
log_warn "请确保您的Android设备满足以下要求：Android 7.0+，至少2GB可用存储空间。"
log_warn "在ZeroTermux中，当出现 (Y/I/N/O/D/Z)[default=?] 或 [Y/N] 时，直接点击回车选择默认选项即可。"

# --- Termux 环境初始化 --- #
log_info "[Termux] 正在安装 proot-distro..."
pkg install proot-distro -y || log_error "proot-distro 安装失败。"

log_info "[Termux] 正在安装 Ubuntu..."
proot-distro install ubuntu || log_error "Ubuntu 安装失败。"

log_info "[Termux] 正在登录到 Ubuntu 环境并执行后续部署步骤..."

# 询问用户是否创建非root用户
read -p "是否要在Ubuntu中创建非root用户？(推荐，Y/n): " CREATE_USER
CREATE_USER=${CREATE_USER:-Y}

USERNAME=""
if [[ "$CREATE_USER" =~ ^[Yy]$ ]]; then
    read -p "请输入您想创建的用户名: " USERNAME
    if [[ -z "$USERNAME" ]]; then
        log_error "用户名不能为空。"
    fi
fi

# 创建一个临时脚本，用于在Ubuntu环境中执行
cat << EOF > ubuntu_deploy_internal.sh
#!/bin/bash

RED=\'\\033[0;31m\'
GREEN=\'\\033[0;32m\'
YELLOW=\'\\033[0;33m\'
NC=\'\\033[0m\' # No Color

log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

log_info "[Ubuntu] 成功进入 Ubuntu 环境。"

# --- Ubuntu 环境初始化 --- #
log_info "[Ubuntu] 正在更新 apt 包列表..."
apt update || log_error "apt update 失败。"

log_info "[Ubuntu] 正在安装必要的软件..."
apt install -y sudo vim git python3-dev python3.12-venv build-essential screen curl python3-pip || log_error "必要软件安装失败。"

USERNAME_TO_CREATE="$USERNAME"
if [[ -n "$USERNAME_TO_CREATE" ]]; then
    log_info "[Ubuntu] 正在创建非root用户: $USERNAME_TO_CREATE ..."
    adduser --disabled-password --gecos "" $USERNAME_TO_CREATE || log_error "创建用户 $USERNAME_TO_CREATE 失败。"
    usermod -aG sudo $USERNAME_TO_CREATE || log_error "添加sudo权限给 $USERNAME_TO_CREATE 失败。"
    log_info "[Ubuntu] 用户 $USERNAME_TO_CREATE 创建成功并已添加sudo权限。"
    log_info "[Ubuntu] 切换到新用户 $USERNAME_TO_CREATE ..."
    # 切换用户后，后续命令将在新用户下执行
    exec su -l $USERNAME_TO_CREATE -c "bash -s" <<\EOF_INNER
    RED=\'\\033[0;31m\'
    GREEN=\'\\033[0;32m\'
    YELLOW=\'\\033[0;33m\'
    NC=\'\\033[0m\' # No Color

    log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
    log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
    log_error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

    log_info "[Ubuntu - $USERNAME_TO_CREATE] 成功切换到用户 $USERNAME_TO_CREATE。"

    # --- 获取必要的文件 --- #
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 正在创建 maimai 文件夹并克隆代码库..."
    mkdir -p ~/maimai || log_error "创建 maimai 文件夹失败。"
    cd ~/maimai || log_error "进入 maimai 文件夹失败。"
    git clone https://github.com/MaiM-with-u/MaiBot.git || log_error "克隆 MaiBot 失败。"
    git clone https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git || log_error "克隆 MaiBot-Napcat-Adapter 失败。"

    # --- 环境配置 (Python & uv) --- #
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 检查 Python 版本..."
    python3 --version || log_error "Python 未安装或版本不正确。"

    log_info "[Ubuntu - $USERNAME_TO_CREATE] 正在安装 uv 包管理器..."
    pip3 install uv --break-system-packages -i https://mirrors.huaweicloud.com/repository/pypi/simple/ || log_error "uv 安装失败。"
    grep -qF \'export PATH=\"$HOME/.local/bin:$PATH\"\' ~/.bashrc || echo \'export PATH=\"$HOME/.local/bin:$PATH\"\' >> ~/.bashrc
    source ~/.bashrc

    # --- 依赖安装 (使用 uv) --- #
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 正在为 MaiBot 安装依赖..."
    cd ~/maimai/MaiBot || log_error "进入 MaiBot 文件夹失败。"
    uv venv || log_error "创建 MaiBot 虚拟环境失败。"
    uv pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple --upgrade || log_error "MaiBot 依赖安装失败。"

    log_info "[Ubuntu - $USERNAME_TO_CREATE] 正在为 MaiBot-Napcat-Adapter 安装依赖..."
    cd ~/maimai/MaiBot-Napcat-Adapter || log_error "进入 MaiBot-Napcat-Adapter 文件夹失败。"
    uv venv || log_error "创建 MaiBot-Napcat-Adapter 虚拟环境失败。"
    uv pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple --upgrade || log_error "MaiBot-Napcat-Adapter 依赖安装失败。"
    cp template/template_config.toml config.toml || log_error "复制 MaiBot-Napcat-Adapter 配置文件失败。"

    # --- NapCat 部署 --- #
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 正在安装 NapCat..."
    curl -o napcat.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh || log_error "下载 NapCat 安装脚本失败。"
    chmod +x napcat.sh
    # 注意：NapCat安装脚本需要sudo权限，这里假设新用户有sudo权限
    ./napcat.sh --docker n --cli y || log_error "NapCat 安装失败。"
    rm napcat.sh

    log_warn "[Ubuntu - $USERNAME_TO_CREATE] NapCat 安装完成。接下来需要手动配置NapCat。"
    log_warn "请运行 \'sudo napcat\'，然后按照文档指示进行配置："
    log_warn "1. 选择 \'配置Napcat\' -> \'配置服务\' -> \'输入QQ号码\' -> \'保存\'"
    log_warn "2. 再次选择 \'配置服务\' -> \'4 WebSocket客户端\'"
    log_warn "3. 名称任意填，Url将\'8082\'修改为\'8095\'，其他保持默认"
    log_warn "4. 选择 \'OK\' -> \'enable\' (使用空格选中) -> \'OK\' -> \'退出\' -> \'启动Napcat\' -> \'启动账号：xxxxxxxxx\'"
    log_warn "5. 截屏二维码，发送/投屏到另一个设备，用登录该QQ号的手机QQ扫码。"
    log_warn "完成后请退出NapCat。"

    # --- 配置 MaiBot 和 Adapter --- #
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 正在配置 MaiBot..."
    cd ~/maimai/MaiBot || log_error "进入 MaiBot 文件夹失败。"
    mkdir -p config || log_error "创建 MaiBot config 文件夹失败。"
    cp template/bot_config_template.toml config/bot_config.toml || log_error "复制 bot_config.toml 失败。"
    cp template/model_config_template.toml config/model_config.toml || log_error "复制 model_config.toml 失败。"
    cp template/template.env .env || log_error "复制 .env 模板失败。"

    log_warn "[Ubuntu - $USERNAME_TO_CREATE] MaiBot 配置文件已复制。请手动编辑 .env 文件，将开头的port改成8000。"
    log_warn "建议您查阅 MaiBot文档中心配置指南 (https://docs.mai-mai.org/manual/config.html) 以完成详细配置。"

    log_info "[Ubuntu - $USERNAME_TO_CREATE] 正在配置 MaiBot-Napcat-Adapter..."
    cd ~/maimai/MaiBot-Napcat-Adapter || log_error "进入 MaiBot-Napcat-Adapter 文件夹失败。"
    # 自动修改 config.toml
    sed -i \'s/^port = 8082/port = 8095/\' config.toml
    sed -i \'/^\[MaiBot_Server\]/a host = "localhost"\\nport = 8000\' config.toml
    sed -i \'/^\[MaiBot_Server\]/a platform_name = "qq"\' config.toml

    log_info "[Ubuntu - $USERNAME_TO_CREATE] MaiBot-Napcat-Adapter 的 config.toml 已自动配置。"
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 部署脚本执行完毕。"
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 您现在可以手动启动MaiBot和Adapter。"
    log_info "[Ubuntu - $USERNAME_TO_CREATE] 祝您使用愉快！"
EOF_INNER
    log_info "[Termux] 用户 $USERNAME_TO_CREATE 的部署流程已完成。"
else
    log_warn "[Ubuntu] 您选择不创建非root用户，将继续使用root用户进行部署。"
    log_warn "[Ubuntu] 直接使用root用户操作所有命令可能有巨大的安全风险，请谨慎操作！"
    
    # --- 在root用户下执行的命令 --- #
    RED=\'\\033[0;31m\'
    GREEN=\'\\033[0;32m\'
    YELLOW=\'\\033[0;33m\'
    NC=\'\\033[0m\' # No Color

    log_info() { echo -e "${GREEN}[INFO] $1${NC}"; }
    log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
    log_error() { echo -e "${RED}[ERROR] $1${NC}"; exit 1; }

    log_info "[Ubuntu - root] 成功进入 Ubuntu 环境。"

    # --- 获取必要的文件 --- #
    log_info "[Ubuntu - root] 正在创建 maimai 文件夹并克隆代码库..."
    mkdir -p ~/maimai || log_error "创建 maimai 文件夹失败。"
    cd ~/maimai || log_error "进入 maimai 文件夹失败。"
    git clone https://github.com/MaiM-with-u/MaiBot.git || log_error "克隆 MaiBot 失败。"
    git clone https://github.com/MaiM-with-u/MaiBot-Napcat-Adapter.git || log_error "克隆 MaiBot-Napcat-Adapter 失败。"

    # --- 环境配置 (Python & uv) --- #
    log_info "[Ubuntu - root] 检查 Python 版本..."
    python3 --version || log_error "Python 未安装或版本不正确。"

    log_info "[Ubuntu - root] 正在安装 uv 包管理器..."
    pip3 install uv --break-system-packages -i https://mirrors.huaweicloud.com/repository/pypi/simple/ || log_error "uv 安装失败。"
    grep -qF \'export PATH=\"$HOME/.local/bin:$PATH\"\' ~/.bashrc || echo \'export PATH=\"$HOME/.local/bin:$PATH\"\' >> ~/.bashrc
    source ~/.bashrc

    # --- 依赖安装 (使用 uv) --- #
    log_info "[Ubuntu - root] 正在为 MaiBot 安装依赖..."
    cd ~/maimai/MaiBot || log_error "进入 MaiBot 文件夹失败。"
    uv venv || log_error "创建 MaiBot 虚拟环境失败。"
    uv pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple --upgrade || log_error "MaiBot 依赖安装失败。"

    log_info "[Ubuntu - root] 正在为 MaiBot-Napcat-Adapter 安装依赖..."
    cd ~/maimai/MaiBot-Napcat-Adapter || log_error "进入 MaiBot-Napcat-Adapter 文件夹失败。"
    uv venv || log_error "创建 MaiBot-Napcat-Adapter 虚拟环境失败。"
    uv pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple --upgrade || log_error "MaiBot-Napcat-Adapter 依赖安装失败。"
    cp template/template_config.toml config.toml || log_error "复制 MaiBot-Napcat-Adapter 配置文件失败。"

    # --- NapCat 部署 --- #
    log_info "[Ubuntu - root] 正在安装 NapCat..."
    curl -o napcat.sh https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh || log_error "下载 NapCat 安装脚本失败。"
    chmod +x napcat.sh
    ./napcat.sh --docker n --cli y || log_error "NapCat 安装失败。"
    rm napcat.sh

    log_warn "[Ubuntu - root] NapCat 安装完成。接下来需要手动配置NapCat。"
    log_warn "请运行 \'sudo napcat\'，然后按照文档指示进行配置："
    log_warn "1. 选择 \'配置Napcat\' -> \'配置服务\' -> \'输入QQ号码\' -> \'保存\'"
    log_warn "2. 再次选择 \'配置服务\' -> \'4 WebSocket客户端\'"
    log_warn "3. 名称任意填，Url将\'8082\'修改为\'8095\'，其他保持默认"
    log_warn "4. 选择 \'OK\' -> \'enable\' (使用空格选中) -> \'OK\' -> \'退出\' -> \'启动Napcat\' -> \'启动账号：xxxxxxxxx\'"
    log_warn "5. 截屏二维码，发送/投屏到另一个设备，用登录该QQ号的手机QQ扫码。"
    log_warn "完成后请退出NapCat。"

    # --- 配置 MaiBot 和 Adapter --- #
    log_info "[Ubuntu - root] 正在配置 MaiBot..."
    cd ~/maimai/MaiBot || log_error "进入 MaiBot 文件夹失败。"
    mkdir -p config || log_error "创建 MaiBot config 文件夹失败。"
    cp template/bot_config_template.toml config/bot_config.toml || log_error "复制 bot_config.toml 失败。"
    cp template/model_config_template.toml config/model_config.toml || log_error "复制 model_config.toml 失败。"
    cp template/template.env .env || log_error "复制 .env 模板失败。"

    log_warn "[Ubuntu - root] MaiBot 配置文件已复制。请手动编辑 .env 文件，将开头的port改成8000。"
    log_warn "建议您查阅 MaiBot文档中心配置指南 (https://docs.mai-mai.org/manual/config.html) 以完成详细配置。"

    log_info "[Ubuntu - root] 正在配置 MaiBot-Napcat-Adapter..."
    cd ~/maimai/MaiBot-Napcat-Adapter || log_error "进入 MaiBot-Napcat-Adapter 文件夹失败。"
    # 自动修改 config.toml
    sed -i \'s/^port = 8082/port = 8095/\' config.toml
    sed -i \'/^\[MaiBot_Server\]/a host = "localhost"\\nport = 8000\' config.toml
    sed -i \'/^\[MaiBot_Server\]/a platform_name = "qq"\' config.toml

    log_info "[Ubuntu - root] MaiBot-Napcat-Adapter 的 config.toml 已自动配置。"
    log_info "[Ubuntu - root] 部署脚本执行完毕。"
    log_info "[Ubuntu - root] 您现在可以手动启动MaiBot和Adapter。"
    log_info "[Ubuntu - root] 祝您使用愉快！"
fi
EOF

chmod +x ubuntu_deploy_internal.sh || log_error "无法为 ubuntu_deploy_internal.sh 添加执行权限。"

# 在Ubuntu环境中执行内部脚本
proot-distro login ubuntu --shared-tmp -- /tmp/ubuntu_deploy_internal.sh || log_error "在Ubuntu中执行部署脚本失败。"

# 清理临时脚本
rm ubuntu_deploy_internal.sh

log_info "[Termux] 脚本执行完成。请手动登录到Ubuntu环境 (proot-distro login ubuntu) 以继续操作。"
log_info "[Termux] 如果您创建了非root用户，请使用 \'su -l <username>\' 切换到该用户。"