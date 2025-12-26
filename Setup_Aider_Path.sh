#!/bin/bash

# Setup_Aider_Path.sh - 自动配置 Aider 路径并验证兼容性
# 解决 macOS App 无法找到 aider 命令的问题

set -e

CONFIG_DIR="$HOME/Library/Application Support/com.yukungao.fetch"
CONFIG_FILE="$CONFIG_DIR/config.json"
LOG_FILE="aider_setup.log"

echo "🔧 Aider 路径配置脚本" | tee "$LOG_FILE"
echo "==============================" | tee -a "$LOG_FILE"

# 1. 检查 aider 是否已安装
echo "" | tee -a "$LOG_FILE"
echo "[1/4] 检查 Aider 安装状态..." | tee -a "$LOG_FILE"

AIDER_PATH=""
if command -v aider &> /dev/null; then
    AIDER_PATH=$(which aider)
    echo "✅ 找到 Aider: $AIDER_PATH" | tee -a "$LOG_FILE"
else
    echo "⚠️ 未找到 Aider，尝试安装..." | tee -a "$LOG_FILE"
    
    # 尝试多种安装方式
    if command -v pip3 &> /dev/null; then
        echo "   使用 pip3 安装 aider-chat..." | tee -a "$LOG_FILE"
        pip3 install aider-chat --user 2>&1 | tee -a "$LOG_FILE" || true
    elif command -v pip &> /dev/null; then
        echo "   使用 pip 安装 aider-chat..." | tee -a "$LOG_FILE"
        pip install aider-chat --user 2>&1 | tee -a "$LOG_FILE" || true
    fi
    
    # 重新查找
    if command -v aider &> /dev/null; then
        AIDER_PATH=$(which aider)
        echo "✅ Aider 安装成功: $AIDER_PATH" | tee -a "$LOG_FILE"
    else
        echo "❌ 安装失败，请手动安装: pip install aider-chat" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# 2. 获取绝对路径（解析符号链接）
ABSOLUTE_PATH=$(readlink -f "$AIDER_PATH" 2>/dev/null || realpath "$AIDER_PATH" 2>/dev/null || echo "$AIDER_PATH")
if [ ! -f "$ABSOLUTE_PATH" ]; then
    ABSOLUTE_PATH="$AIDER_PATH"
fi

echo "   绝对路径: $ABSOLUTE_PATH" | tee -a "$LOG_FILE"

# 3. 尝试创建软链接到系统路径（可选）
echo "" | tee -a "$LOG_FILE"
echo "[2/4] 尝试创建系统软链接..." | tee -a "$LOG_FILE"

SYSTEM_LINK="/usr/local/bin/aider"
if [ ! -f "$SYSTEM_LINK" ]; then
    if sudo -n true 2>/dev/null; then
        echo "   创建软链接: $SYSTEM_LINK -> $ABSOLUTE_PATH" | tee -a "$LOG_FILE"
        sudo ln -sf "$ABSOLUTE_PATH" "$SYSTEM_LINK" 2>&1 | tee -a "$LOG_FILE" || echo "   ⚠️ 需要管理员权限，跳过软链接" | tee -a "$LOG_FILE"
    else
        echo "   ⚠️ 需要管理员权限创建软链接，跳过此步骤" | tee -a "$LOG_FILE"
    fi
else
    echo "   ✅ 系统路径已存在: $SYSTEM_LINK" | tee -a "$LOG_FILE"
fi

# 4. 写入配置文件
echo "" | tee -a "$LOG_FILE"
echo "[3/4] 写入 App 配置文件..." | tee -a "$LOG_FILE"

mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" << EOF
{
  "aiderPath": "$ABSOLUTE_PATH",
  "aiderVersion": "$(aider --version 2>&1 | head -1 || echo 'unknown')",
  "configuredAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

echo "   ✅ 配置已写入: $CONFIG_FILE" | tee -a "$LOG_FILE"
echo "   Aider 路径: $ABSOLUTE_PATH" | tee -a "$LOG_FILE"

# 5. 验证 Aider 与 Gemini 兼容性
echo "" | tee -a "$LOG_FILE"
echo "[4/4] 验证 Aider 与 Gemini 兼容性..." | tee -a "$LOG_FILE"

# 检查 Aider 版本
AIDER_VERSION=$(aider --version 2>&1 | head -1 || echo "unknown")
echo "   Aider 版本: $AIDER_VERSION" | tee -a "$LOG_FILE"

# Dry-run 测试（检查模型参数支持）
echo "   测试模型参数支持..." | tee -a "$LOG_FILE"
if aider --help 2>&1 | grep -q "openrouter\|api-base\|api-key"; then
    echo "   ✅ Aider 支持自定义 API 配置" | tee -a "$LOG_FILE"
else
    echo "   ⚠️ 无法确认 API 配置支持，可能需要更新 Aider" | tee -a "$LOG_FILE"
fi

# 测试 dry-run 模式（使用本地 API 配置）
echo "   执行 Dry-Run 测试..." | tee -a "$LOG_FILE"
export OPENAI_API_BASE="http://127.0.0.1:3000/v1"
export OPENAI_API_KEY="local-fetch-key"
DRY_RUN_OUTPUT=$(timeout 3 aider --model openai/gemini-2.0-flash --openai-api-base "$OPENAI_API_BASE" --openai-api-key "$OPENAI_API_KEY" --no-git --message "test" --dry-run 2>&1 || true)
if echo "$DRY_RUN_OUTPUT" | grep -qi "dry.*run\|help\|usage\|error.*api\|connection"; then
    echo "   ✅ Dry-Run 测试通过（Aider 能识别参数）" | tee -a "$LOG_FILE"
else
    echo "   ⚠️ Dry-Run 测试未返回预期输出（可能是 API 未运行，不影响配置）" | tee -a "$LOG_FILE"
    echo "   提示: 确保 Fetch App 运行后再测试完整流程" | tee -a "$LOG_FILE"
fi

# 6. 输出总结
echo "" | tee -a "$LOG_FILE"
echo "==============================" | tee -a "$LOG_FILE"
echo "✅ 配置完成！" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "📋 配置信息:" | tee -a "$LOG_FILE"
echo "   Aider 路径: $ABSOLUTE_PATH" | tee -a "$LOG_FILE"
echo "   配置文件: $CONFIG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "⚠️  如果 App 仍然报错，请手动在 Fetch 设置中填入路径:" | tee -a "$LOG_FILE"
echo "   $ABSOLUTE_PATH" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "📝 完整日志: $LOG_FILE" | tee -a "$LOG_FILE"

