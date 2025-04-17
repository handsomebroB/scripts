#!/bin/sh
echo "欢迎使用 IPv6 到 IPv4 NAT 转发设置脚本"
echo "此脚本将帮助您配置端口转发规则。"
echo "-------------------------------------------------------"

# 检测依赖项
echo "检查依赖项..."
if ! command -v ip >/dev/null; then
    echo "错误：未找到 'ip' 命令。请安装 'iproute2' 包。"
    echo "运行：opkg update && opkg install iproute2"
    exit 1
fi
if ! command -v nft >/dev/null; then
    echo "错误：未找到 'nft' 命令。请安装 'nftables' 包。"
    echo "运行：opkg update && opkg install nftables"
    exit 1
fi
if ! command -v awk >/dev/null; then
    echo "错误：未找到 'awk' 命令。请安装 'busybox' 或兼容包。"
    exit 1
fi
echo "依赖项检查通过。"

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "警告：此脚本需要 root 权限来应用 nftables 规则。请以 root 用户或使用 sudo 运行脚本。"
    echo "是否继续？（y/n）"
    read CONTINUE_ROOT
    if [ "$CONTINUE_ROOT" != "y" ] && [ "$CONTINUE_ROOT" != "Y" ]; then
        echo "脚本已退出。请以 root 权限重新运行。"
        exit 1
    fi
fi

# 存储规则的临时文件
RULES_FILE="/tmp/nat_forward_rules"
> "$RULES_FILE"

# 循环添加规则
while true; do
    echo "-------------------------------------------------------"
    echo "列出可用的网络接口："
    # 获取网络接口列表，确保按行分割
    INTERFACES=$(ip link show | grep '^[0-9]' | cut -d: -f2 | awk '{print $1}' | grep -v 'lo')
    if [ -z "$INTERFACES" ]; then
        echo "错误：未找到网络接口。请检查您的网络配置。"
        exit 1
    fi
    # 使用临时文件存储接口列表，确保换行符不丢失
    echo "$INTERFACES" > /tmp/interfaces_list
    awk '{printf "%2d. %s\n", NR, $0}' /tmp/interfaces_list
    echo "-------------------------------------------------------"
    echo "请选择一个接口编号（例如，1）："
    MAX_RETRIES=3
    RETRY_COUNT=0
    IF_NAME=""
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        read IF_NUM
        if ! echo "$IF_NUM" | grep -q '^[0-9]\+$'; then
            echo "错误：请输入有效的数字编号。请重试。"
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
                echo "错误：无效尝试次数过多。退出。"
                exit 1
            fi
            continue
        fi
        # 使用 awk 从临时文件中提取指定行，确保换行符不影响结果
        IF_NAME=$(awk 'NR=='"$IF_NUM"' {print $0}' /tmp/interfaces_list)
        if [ -z "$IF_NAME" ]; then
            echo "错误：无效的选择。请重试。"
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
                echo "错误：无效尝试次数过多。退出。"
                exit 1
            fi
            continue
        fi
        # 验证网卡是否存在
        if ! ip link show "$IF_NAME" >/dev/null 2>&1; then
            echo "错误：接口 '$IF_NAME' 不存在。请重试。"
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
                echo "错误：无效尝试次数过多。退出。"
                exit 1
            fi
            continue
        fi
        break
    done
    echo "选择的接口：$IF_NAME"

    # 获取接口的 IPv6 地址（仅供参考）
    IPV6_ADDR=$(ip -6 addr show dev "$IF_NAME" | awk '/inet6/ {split($2, a, "/"); print a[1]}' | head -1)
    if [ -z "$IPV6_ADDR" ]; then
        echo "警告：未找到 $IF_NAME 的 IPv6 地址。地址将在运行时动态获取。"
    else
        echo "当前 $IF_NAME 的 IPv6 地址：$IPV6_ADDR（将在运行时动态更新）"
    fi

    # 提示输入源端口
    echo "请输入要转发的源端口（例如，5858）："
    read SRC_PORT
    if ! echo "$SRC_PORT" | grep -q '^[0-9]\+$' || [ "$SRC_PORT" -lt 1 ] || [ "$SRC_PORT" -gt 65535 ]; then
        echo "错误：无效的端口号。必须在 1 到 65535 之间。"
        continue
    fi

    # 提示输入目标 IP
    echo "请输入目标 IPv4 地址（例如，192.168.8.8）："
    read DEST_IP
    if ! echo "$DEST_IP" | grep -q '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$'; then
        echo "错误：无效的 IPv4 地址格式。"
        continue
    fi

    # 提示输入目标端口
    echo "请输入目标端口（例如，8080）："
    read DEST_PORT
    if ! echo "$DEST_PORT" | grep -q '^[0-9]\+$' || [ "$DEST_PORT" -lt 1 ] || [ "$DEST_PORT" -gt 65535 ]; then
        echo "错误：无效的端口号。必须在 1 到 65535 之间。"
        continue
    fi

    # 提示输入协议
    echo "请输入协议（tcp 或 udp）："
    read PROTO
    if [ "$PROTO" != "tcp" ] && [ "$PROTO" != "udp" ]; then
        echo "错误：协议必须是 'tcp' 或 'udp'。"
        continue
    fi

    # 保存规则
    echo "$IF_NAME:$SRC_PORT:$DEST_IP:$DEST_PORT:$PROTO" >> "$RULES_FILE"
    echo "规则已添加：$IF_NAME:IPv6:$SRC_PORT -> $DEST_IP:$DEST_PORT ($PROTO)"

    # 询问是否继续添加规则
    echo "是否要添加另一条转发规则？（y/n）"
    read CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        break
    fi
done

# 复制规则文件到永久存储
cp "$RULES_FILE" "/etc/nat_forward_rules"
echo "规则已保存到 /etc/nat_forward_rules"

# 清理旧的状态文件和规则
rm -f /tmp/ipv6_nat_status 2>/dev/null || true
rm -f /tmp/ipv6_nat_address_* 2>/dev/null || true
nft flush table inet my_nat_table 2>/dev/null || true
nft delete table inet my_nat_table 2>/dev/null || true
echo "已清除旧状态和规则（如果有）。"

# 提示用户是否需要加入 hotplug 配置
echo "是否要添加 hotplug 配置以支持动态接口事件？（y/n）"
echo "注意：这将在网络接口准备好时自动应用规则，对于 PPPoE 拨号场景至关重要。"
read USE_HOTPLUG
HOTPLUG_SCRIPT="/etc/hotplug.d/iface/99-ipv6-nat-forward"
if [ "$USE_HOTPLUG" = "y" ] || [ "$USE_HOTPLUG" = "Y" ]; then
    echo "检查 hotplug.d 兼容性..."
    if [ -d "/etc/hotplug.d" ] && command -v hotplug-call >/dev/null 2>&1; then
        echo "支持 hotplug.d。配置 hotplug 事件触发。"
        # 检查是否已存在 hotplug 脚本
        if [ -f "$HOTPLUG_SCRIPT" ]; then
            echo "警告：hotplug 脚本 $HOTPLUG_SCRIPT 已存在。是否覆盖？（y/n）"
            read OVERWRITE_HOTPLUG
            if [ "$OVERWRITE_HOTPLUG" != "y" ] && [ "$OVERWRITE_HOTPLUG" != "Y" ]; then
                echo "不覆盖现有 hotplug 脚本，跳过配置。"
                USE_HOTPLUG="n"
            fi
        fi
        if [ "$USE_HOTPLUG" = "y" ] || [ "$USE_HOTPLUG" = "Y" ]; then
            # 生成 hotplug 脚本
            mkdir -p /etc/hotplug.d/iface 2>/dev/null || true
            cat > "$HOTPLUG_SCRIPT" << 'EOF'
#!/bin/sh
# 监听网络接口事件，应用 NAT 转发规则
[ "$ACTION" = "ifup" ] || exit 0

# 检查规则文件是否存在
RULES_FILE="/etc/nat_forward_rules"
if [ ! -f "$RULES_FILE" ]; then
    logger -t ipv6_nat "规则文件未找到。跳过。"
    exit 1
fi

# 检查接口是否在规则文件中
# INTERFACE 是 hotplug 提供的环境变量，表示触发事件的接口
grep "^$INTERFACE:" "$RULES_FILE" >/dev/null || exit 0

logger -t ipv6_nat "接口 $INTERFACE 已启动。检查并应用 NAT 转发规则。"

# 获取当前 IPv6 地址
IPV6_ADDR=$(ip -6 addr show dev "$INTERFACE" | awk '/inet6/ {split($2, a, "/"); print a[1]}' | head -1)
if [ -z "$IPV6_ADDR" ]; then
    logger -t ipv6_nat "未找到 $INTERFACE 的 IPv6 地址。跳过。"
    exit 0
fi

# 检查规则是否已成功应用，且是否基于当前 IPv6 地址
STATUS_FILE="/tmp/ipv6_nat_status"
ADDRESS_FILE="/tmp/ipv6_nat_address_$INTERFACE"
if [ -f "$STATUS_FILE" ] && grep -q "success" "$STATUS_FILE" && [ -f "$ADDRESS_FILE" ] && grep -q "$IPV6_ADDR" "$ADDRESS_FILE"; then
    logger -t ipv6_nat "接口 $INTERFACE 已启动，NAT 规则已成功应用，当前 IPv6 地址为 $IPV6_ADDR。跳过。"
    exit 0
fi

logger -t ipv6_nat "接口 $INTERFACE 已启动。为 IPv6 地址 $IPV6_ADDR 应用 NAT 转发规则。"

# 清理旧规则（无论是否成功应用，都清理以避免重复规则）
nft flush table inet my_nat_table 2>/dev/null || true
nft delete table inet my_nat_table 2>/dev/null || true
nft add table inet my_nat_table 2>/dev/null || true
nft add chain inet my_nat_table nat { type nat hook prerouting priority 0 \; } 2>/dev/null || true
nft add chain inet my_nat_table postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true

# 计数成功应用的规则数量
SUCCESS_COUNT=0
TOTAL_RULES=$(wc -l < "$RULES_FILE")

# 应用每个规则
while IFS=':' read -r IF_NAME SRC_PORT DEST_IP DEST_PORT PROTO; do
    # 仅处理与当前接口相关的规则
    if [ "$IF_NAME" = "$INTERFACE" ]; then
        logger -t ipv6_nat "为 $IF_NAME 应用规则，IPv6 地址 $IPV6_ADDR: $SRC_PORT -> $DEST_IP:$DEST_PORT ($PROTO)"
        DNAT_ERROR=$(nft add rule inet my_nat_table nat iifname "$IF_NAME" ip6 daddr $IPV6_ADDR $PROTO dport $SRC_PORT dnat to $DEST_IP:$DEST_PORT 2>&1)
        if [ $? -eq 0 ]; then
            logger -t ipv6_nat "DNAT 规则已为 $IF_NAME 应用。"
        else
            logger -t ipv6_nat "无法为 $IF_NAME 应用 DNAT 规则。错误信息: $DNAT_ERROR"
        fi
        SNAT_ERROR=$(nft add rule inet my_nat_table postrouting ip saddr $DEST_IP $PROTO sport $DEST_PORT snat to $IPV6_ADDR 2>&1)
        if [ $? -eq 0 ]; then
            logger -t ipv6_nat "SNAT 规则已为 $IF_NAME 应用。"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            logger -t ipv6_nat "无法为 $IF_NAME 应用 SNAT 规则。错误信息: $SNAT_ERROR"
        fi
    fi
done < "$RULES_FILE"

# 更新状态文件和地址 Ascend
if [ $SUCCESS_COUNT -eq $TOTAL_RULES ]; then
    echo "success" > "$STATUS_FILE"
    echo "$IPV6_ADDR" > "$ADDRESS_FILE"
    logger -t ipv6_nat "所有 $SUCCESS_COUNT/$TOTAL_RULES 条 IPv6 NAT 转发规则通过 hotplug 成功应用，地址为 $IPV6_ADDR。"
else
    echo "partial" > "$STATUS_FILE"
    echo "$IPV6_ADDR" > "$ADDRESS_FILE"
    logger -t ipv6_nat "仅 $SUCCESS_COUNT/$TOTAL_RULES 条 IPv6 NAT 转发规则通过 hotplug 应用，地址为 $IPV6_ADDR。"
fi
EOF
            # 赋予 hotplug 脚本执行权限
            chmod +x "$HOTPLUG_SCRIPT" 2>/dev/null || true
            echo "Hotplug 脚本已创建于 $HOTPLUG_SCRIPT。"
        fi
    else
        echo "警告：此系统不支持 hotplug.d。"
        USE_HOTPLUG="n"
    fi
fi

# 无论是否配置 hotplug，都询问是否需要 cron 作为备用
echo "是否要添加 cron 任务以定期检查并应用规则？（y/n）"
echo "注意：这将定期检查接口状态和规则应用情况，作为备用机制。"
read USE_CRON
if [ "$USE_CRON" = "y" ] || [ "$USE_CRON" = "Y" ]; then
    # 检查 cron 功能是否可用
    if ! command -v crontab >/dev/null; then
        echo "错误：未找到 'crontab' 命令。cron 功能不可用，无法配置定时任务。"
        echo "请手动安装 cron 相关包（如 cronie 或 busybox），然后重新运行脚本。"
        USE_CRON="n"
    else
        echo "cron 功能已检测到，将使用现有功能配置定时任务。"
        # 提示用户选择 cron 任务的时间间隔
        echo "请输入 cron 任务的时间间隔（分钟，例如，5 表示每 5 分钟，推荐）："
        read CRON_INTERVAL
        if ! echo "$CRON_INTERVAL" | grep -q '^[0-9]\+$' || [ "$CRON_INTERVAL" -lt 1 ] || [ "$CRON_INTERVAL" -gt 60 ]; then
            echo "无效的间隔。使用默认间隔 5 分钟。"
            CRON_INTERVAL=5
        fi
        # 确定 cron 脚本路径，优先使用 /etc/cron.d/，如果不可用则使用 /etc/
        CRON_SCRIPT="/etc/cron.d/ipv6_nat_forward.sh"
        CRON_DIR="/etc/cron.d"
        if ! mkdir -p "$CRON_DIR" 2>/dev/null; then
            echo "警告：无法创建 $CRON_DIR 目录，将使用备用路径 /etc/。"
            CRON_SCRIPT="/etc/ipv6_nat_forward.sh"
        fi
        # 检查是否已存在 cron 脚本
        if [ -f "$CRON_SCRIPT" ]; then
            echo "警告：cron 脚本 $CRON_SCRIPT 已存在。是否覆盖？（y/n）"
            read OVERWRITE_CRON
            if [ "$OVERWRITE_CRON" != "y" ] && [ "$OVERWRITE_CRON" != "Y" ]; then
                echo "不覆盖现有 cron 脚本，跳过配置。"
                USE_CRON="n"
            fi
        fi
        if [ "$USE_CRON" = "y" ] || [ "$USE_CRON" = "Y" ]; then
            # 创建 cron 脚本
            cat > "$CRON_SCRIPT" << 'EOF'
#!/bin/sh
RULES_FILE="/etc/nat_forward_rules"
STATUS_FILE="/tmp/ipv6_nat_status"
SUCCESS_COUNT=0
TOTAL_RULES=$(wc -l < "$RULES_FILE")
NEED_UPDATE=0
while IFS=":" read -r IF_NAME SRC_PORT DEST_IP DEST_PORT PROTO; do
    ADDRESS_FILE="/tmp/ipv6_nat_address_$IF_NAME"
    IPV6_ADDR=$(ip -6 addr show dev "$IF_NAME" | awk '/inet6/ {split($2, a, "/"); print a[1]}' | head -1)
    if [ -n "$IPV6_ADDR" ] && ( [ ! -f "$ADDRESS_FILE" ] || ! grep -q "$IPV6_ADDR" "$ADDRESS_FILE" ) || ( [ ! -f "$STATUS_FILE" ] || ! grep -q "success" "$STATUS_FILE" ); then
        NEED_UPDATE=1
        break
    fi
done < "$RULES_FILE"
if [ $NEED_UPDATE -eq 1 ]; then
    nft flush table inet my_nat_table 2>/dev/null || true
    nft delete table inet my_nat_table 2>/dev/null || true
    nft add table inet my_nat_table 2>/dev/null || true
    nft add chain inet my_nat_table nat { type nat hook prerouting priority 0 \; } 2>/dev/null || true
    nft add chain inet my_nat_table postrouting { type nat hook postrouting priority 100 \; } 2>/dev/null || true
    while IFS=":" read -r IF_NAME SRC_PORT DEST_IP DEST_PORT PROTO; do
        ADDRESS_FILE="/tmp/ipv6_nat_address_$IF_NAME"
        IPV6_ADDR=$(ip -6 addr show dev "$IF_NAME" | awk '/inet6/ {split($2, a, "/"); print a[1]}' | head -1)
        if [ -n "$IPV6_ADDR" ]; then
            logger -t ipv6_nat "尝试通过 cron 为 $IF_NAME 应用规则，IPv6 地址为 $IPV6_ADDR: $SRC_PORT -> $DEST_IP:$DEST_PORT ($PROTO)"
            DNAT_ERROR=$(nft add rule inet my_nat_table nat iifname "$IF_NAME" ip6 daddr $IPV6_ADDR $PROTO dport $SRC_PORT dnat to $DEST_IP:$DEST_PORT 2>&1)
            if [ $? -eq 0 ]; then
                logger -t ipv6_nat "DNAT 规则已通过 cron 为 $IF_NAME 应用。"
            else
                logger -t ipv6_nat "无法通过 cron 为 $IF_NAME 应用 DNAT 规则。错误信息: $DNAT_ERROR"
            fi
            SNAT_ERROR=$(nft add rule inet my_nat_table postrouting ip saddr $DEST_IP $PROTO sport $DEST_PORT snat to $IPV6_ADDR 2>&1)
            if [ $? -eq 0 ]; then
                logger -t ipv6_nat "SNAT 规则已通过 cron 为 $IF_NAME 应用。"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                logger -t ipv6_nat "无法通过 cron 为 $IF_NAME 应用 SNAT 规则。错误信息: $SNAT_ERROR"
            fi
        else
            logger -t ipv6_nat "未找到 $IF_NAME 的 IPv6 地址，跳过规则应用。"
        fi
    done < "$RULES_FILE"
    if [ $SUCCESS_COUNT -eq $TOTAL_RULES ]; then
        echo "success" > "$STATUS_FILE"
        logger -t ipv6_nat "所有 $SUCCESS_COUNT/$TOTAL_RULES 条规则通过 cron 应用。"
    else
        echo "partial" > "$STATUS_FILE"
        logger -t ipv6_nat "仅 $SUCCESS_COUNT/$TOTAL_RULES 条规则通过 cron 应用。"
    fi
fi
EOF
            chmod +x "$CRON_SCRIPT" 2>/dev/null || true
            # 添加定时任务
            CRON_JOB="*/$CRON_INTERVAL * * * * $CRON_SCRIPT"
            (crontab -l 2>/dev/null | grep -v "ipv6_nat_forward"; echo "$CRON_JOB") | crontab -
            echo "Cron 任务已添加，每 $CRON_INTERVAL 分钟检查并应用规则（如果未成功或 IPv6 地址变更）。"
            echo "注意：cron 任务对系统性能影响极小（CPU 和内存使用量可忽略）。"
        fi
    fi
else
    if [ "$USE_HOTPLUG" != "y" ] && [ "$USE_HOTPLUG" != "Y" ]; then
        echo "警告：没有 hotplug 或 cron，规则将不会自动应用。您需要手动应用它们。"
    fi
fi

# 询问是否立即应用规则
echo "是否要立即应用规则？（y/n）"
read APPLY_NOW
if [ "$APPLY_NOW" = "y" ] || [ "$APPLY_NOW" = "Y" ]; then
    # 直接应用规则
    echo "正在直接应用规则..."
    APPLY_SCRIPT="/tmp/apply_nat_rules.sh"
    cat > "$APPLY_SCRIPT" << 'EOF'
#!/bin/sh
RULES_FILE="/etc/nat_forward_rules"
STATUS_FILE="/tmp/ipv6_nat_status"
nft flush table inet my_nat_table 2>/dev/null || true
nft delete table inet my_nat_table 2>/dev/null || true
logger -t ipv6_nat "已清理旧的 NAT 表和规则。"
TABLE_ERROR=$(nft add table inet my_nat_table 2>&1)
if [ $? -eq 0 ]; then
    logger -t ipv6_nat "成功创建 NAT 表 my_nat_table。"
else
    logger -t ipv6_nat "创建 NAT 表 my_nat_table 失败。错误信息: $TABLE_ERROR"
fi
PRE_ERROR=$(nft add chain inet my_nat_table nat { type nat hook prerouting priority 0 \; } 2>&1)
if [ $? -eq 0 ]; then
    logger -t ipv6_nat "成功创建 prerouting 链。"
else
    logger -t ipv6_nat "创建 prerouting 链失败。错误信息: $PRE_ERROR"
fi
POST_ERROR=$(nft add chain inet my_nat_table postrouting { type nat hook postrouting priority 100 \; } 2>&1)
if [ $? -eq 0 ]; then
    logger -t ipv6_nat "成功创建 postrouting 链。"
else
    logger -t ipv6_nat "创建 postrouting 链失败。错误信息: $POST_ERROR"
fi
SUCCESS_COUNT=0
TOTAL_RULES=$(wc -l < "$RULES_FILE")
while IFS=":" read -r IF_NAME SRC_PORT DEST_IP DEST_PORT PROTO; do
    IPV6_ADDR=$(ip -6 addr show dev "$IF_NAME" | awk '/inet6/ {split($2, a, "/"); print a[1]}' | head -1)
    ADDRESS_FILE="/tmp/ipv6_nat_address_$IF_NAME"
    if [ -n "$IPV6_ADDR" ]; then
        logger -t ipv6_nat "尝试为 $IF_NAME 应用规则，IPv6 地址为 $IPV6_ADDR: $SRC_PORT -> $DEST_IP:$DEST_PORT ($PROTO)"
        DNAT_ERROR=$(nft add rule inet my_nat_table nat iifname "$IF_NAME" ip6 daddr $IPV6_ADDR $PROTO dport $SRC_PORT dnat to $DEST_IP:$DEST_PORT 2>&1)
        if [ $? -eq 0 ]; then
            logger -t ipv6_nat "DNAT 规则已手动为 $IF_NAME 应用。"
        else
            logger -t ipv6_nat "无法为 $IF_NAME 应用 DNAT 规则。错误信息: $DNAT_ERROR"
        fi
        SNAT_ERROR=$(nft add rule inet my_nat_table postrouting ip saddr $DEST_IP $PROTO sport $DEST_PORT snat to $IPV6_ADDR 2>&1)
        if [ $? -eq 0 ]; then
            logger -t ipv6_nat "SNAT 规则已手动为 $IF_NAME 应用。"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            logger -t ipv6_nat "无法为 $IF_NAME 应用 SNAT 规则。错误信息: $SNAT_ERROR"
        fi
        echo "$IPV6_ADDR" > "$ADDRESS_FILE"
    else
        logger -t ipv6_nat "未找到 $IF_NAME 的 IPv6 地址，跳过规则应用。"
    fi
done < "$RULES_FILE"
if [ $SUCCESS_COUNT -eq $TOTAL_RULES ]; then
    echo "success" > "$STATUS_FILE"
    logger -t ipv6_nat "所有 $SUCCESS_COUNT/$TOTAL_RULES 条规则已手动应用。"
else
    echo "partial" > "$STATUS_FILE"
    logger -t ipv6_nat "仅 $SUCCESS_COUNT/$TOTAL_RULES 条规则已手动应用。"
fi
# 检查规则是否成功应用
if nft list table inet my_nat_table 2>/dev/null; then
    logger -t ipv6_nat "NAT 表 my_nat_table 已成功创建，规则应用完成。"
else
    logger -t ipv6_nat "无法找到 NAT 表 my_nat_table，规则应用可能失败。"
fi
EOF
    chmod +x "$APPLY_SCRIPT" 2>/dev/null || true
    /bin/sh "$APPLY_SCRIPT"
    echo "规则已应用。使用 'logread | grep ipv6_nat' 查看详细日志。"
    echo "您也可以使用 'nft list ruleset' 检查 NAT 规则是否正确加载。"
    echo "如果转发仍未生效，请检查系统防火墙设置或与其他规则的冲突。"
fi

echo "设置完成。规则将通过 hotplug 或 cron 应用（如果已配置）。"
