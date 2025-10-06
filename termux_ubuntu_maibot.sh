#!/data/data/com.termux/files/usr/bin/bash
# ======================================================
# MaiBot MMC Android 一键安装脚本 (Termux)
# 作者: 清 白专用版
# ======================================================

echo "🌈 正在安装 MaiBot MMC Android 环境..."
sleep 1

# -----------------------------------------------
# 1. 更新系统与依赖
# -----------------------------------------------
pkg update -y && pkg upgrade -y
pkg install -y git python nodejs ffmpeg curl

# 检查 Python 是否可用
if ! command -v python &>/dev/null; then
    echo "❌ 未检测到 Python，请手动安装。"
    exit 1
fi

# -----------------------------------------------
# 2. 创建项目目录
# -----------------------------------------------
cd ~
mkdir -p MaiBot && cd MaiBot

# -----------------------------------------------
# 3. 克隆 MMC 仓库
# -----------------------------------------------
if [ ! -d "MaiBot-MMC" ]; then
    echo "📥 正在下载 MaiBot-MMC ..."
    git clone git clone https://github.com/MaiM-with-u/MaiBot.git
else
    echo "📁 检测到已存在 MaiBot-MMC 目录，跳过下载。"
fi

cd MaiBot-MMC

# -----------------------------------------------
# 4. 创建 Python 虚拟环境
# -----------------------------------------------
echo "🧩 创建 Python 虚拟环境..."
python -m venv .venv
source .venv/bin/activate

# -----------------------------------------------
# 5. 安装依赖
# -----------------------------------------------
echo "📦 正在安装 Python 依赖..."
pip install -U pip
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    echo "⚠️ 未找到 requirements.txt，跳过。"
fi

# 安装 Node 模块（如果存在）
if [ -f "package.json" ]; then
    echo "📦 正在安装 Node 模块..."
    npm install
fi

# -----------------------------------------------
# 6. 用户配置
# -----------------------------------------------
echo ""
echo "⚙️ 请输入配置信息："
read -p "🔑 OpenAI API Key: " OPENAI_KEY
read -p "🤖 Bot Token: " BOT_TOKEN

cat > .env <<EOF
OPENAI_API_KEY=${OPENAI_KEY}
BOT_TOKEN=${BOT_TOKEN}
EOF

echo "✅ 配置已保存到 .env"

# -----------------------------------------------
# 7. 启动 MaiBot MMC
# -----------------------------------------------
echo ""
echo "🚀 启动 MaiBot MMC..."
python main.py

echo ""
echo "🎉 安装完成！如需重新启动，请执行："
echo "cd ~/MaiBot/MaiBot-MMC && source .venv/bin/activate && python main.py"
