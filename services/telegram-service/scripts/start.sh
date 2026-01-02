#!/usr/bin/env bash
# telegram-service 启动/守护一体脚本
# 用法: ./scripts/start.sh {start|stop|status|daemon}

set -uo pipefail

# ==================== 配置区 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
RUN_DIR="$SERVICE_DIR/pids"
LOG_DIR="$SERVICE_DIR/logs"
DAEMON_PID="$RUN_DIR/daemon.pid"
DAEMON_LOG="$LOG_DIR/daemon.log"
SERVICE_PID="$RUN_DIR/bot.pid"
SERVICE_LOG="$LOG_DIR/bot.log"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
STOP_TIMEOUT=10

# 加载环境变量
if [ -f "$SERVICE_DIR/config/.env" ]; then
    set -a
    source "$SERVICE_DIR/config/.env"
    set +a
fi

# 启动命令
START_CMD="python3 -m src.main"

# 环境变量（代理等）
# export HTTPS_PROXY=http://127.0.0.1:9910
# export HTTP_PROXY=http://127.0.0.1:9910

# ==================== 工具函数 ====================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$DAEMON_LOG"
}

init_dirs() {
    mkdir -p "$RUN_DIR" "$LOG_DIR"
}

read_pid() {
    local pid_file="$1"
    [ -f "$pid_file" ] && cat "$pid_file" || echo ""
}

is_running() {
    local pid="$1"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

get_uptime() {
    local pid="$1"
    if is_running "$pid"; then
        local start_time=$(ps -o lstart= -p "$pid" 2>/dev/null)
        if [ -n "$start_time" ]; then
            local start_sec=$(date -d "$start_time" +%s 2>/dev/null)
            local now_sec=$(date +%s)
            local diff=$((now_sec - start_sec))
            printf "%dd %dh %dm" $((diff/86400)) $((diff%86400/3600)) $((diff%3600/60))
        fi
    fi
}

# ==================== 服务控制 ====================
start_service() {
    local pid=$(read_pid "$SERVICE_PID")
    
    if is_running "$pid"; then
        echo "Bot 已运行 (PID: $pid)"
        return 0
    fi
    
    cd "$SERVICE_DIR"
    source .venv/bin/activate
    PYTHONPATH=src nohup $START_CMD >> "$SERVICE_LOG" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$SERVICE_PID"
    
    sleep 1
    if is_running "$new_pid"; then
        log "START Bot (PID: $new_pid)"
        echo "✓ Bot 已启动 (PID: $new_pid)"
        return 0
    else
        log "ERROR Bot 启动失败"
        echo "✗ Bot 启动失败"
        rm -f "$SERVICE_PID"
        return 1
    fi
}

stop_service() {
    local pid=$(read_pid "$SERVICE_PID")
    
    if ! is_running "$pid"; then
        rm -f "$SERVICE_PID"
        echo "Bot 未运行"
        return 0
    fi
    
    # 优雅停止
    kill -TERM "$pid" 2>/dev/null
    local waited=0
    while is_running "$pid" && [ $waited -lt $STOP_TIMEOUT ]; do
        sleep 1
        ((waited++))
    done
    
    # 强制停止
    if is_running "$pid"; then
        kill -KILL "$pid" 2>/dev/null
        log "KILL Bot (PID: $pid) 强制终止"
    else
        log "STOP Bot (PID: $pid)"
    fi
    
    rm -f "$SERVICE_PID"
    echo "✓ Bot 已停止"
}

status_service() {
    local pid=$(read_pid "$SERVICE_PID")
    if is_running "$pid"; then
        local uptime=$(get_uptime "$pid")
        echo "✓ Bot 运行中 (PID: $pid, 运行: $uptime)"
        echo ""
        echo "=== 最近日志 ==="
        tail -10 "$SERVICE_LOG" 2>/dev/null
    else
        [ -f "$SERVICE_PID" ] && rm -f "$SERVICE_PID"
        echo "✗ Bot 未运行"
    fi
}

# ==================== 守护进程 ====================
monitor_loop() {
    log "=== 守护进程启动 (间隔: ${CHECK_INTERVAL}s) ==="
    while true; do
        local pid=$(read_pid "$SERVICE_PID")
        if ! is_running "$pid"; then
            [ -f "$SERVICE_PID" ] && rm -f "$SERVICE_PID"
            log "CHECK Bot 未运行，重启..."
            start_service > /dev/null
        fi
        sleep "$CHECK_INTERVAL"
    done
}

daemon_start() {
    local pid=$(read_pid "$DAEMON_PID")
    if is_running "$pid"; then
        echo "守护进程已运行 (PID: $pid)"
        return 0
    fi
    
    init_dirs
    start_service
    
    nohup "$0" _monitor >> "$DAEMON_LOG" 2>&1 &
    echo $! > "$DAEMON_PID"
    echo "守护进程已启动 (PID: $!)"
}

daemon_stop() {
    local pid=$(read_pid "$DAEMON_PID")
    if is_running "$pid"; then
        kill -TERM "$pid" 2>/dev/null
        rm -f "$DAEMON_PID"
        log "STOP 守护进程 (PID: $pid)"
        echo "守护进程已停止"
    else
        rm -f "$DAEMON_PID"
        echo "守护进程未运行"
    fi
    stop_service
}

daemon_status() {
    local pid=$(read_pid "$DAEMON_PID")
    if is_running "$pid"; then
        local uptime=$(get_uptime "$pid")
        echo "守护进程: 运行中 (PID: $pid, 运行: $uptime)"
    else
        [ -f "$DAEMON_PID" ] && rm -f "$DAEMON_PID"
        echo "守护进程: 未运行"
    fi
    echo ""
    status_service
}

# ==================== 入口 ====================
init_dirs
cd "$SERVICE_DIR"

case "${1:-help}" in
    start)    start_service ;;
    stop)     stop_service ;;
    status)   status_service ;;
    restart)  stop_service; sleep 1; start_service ;;
    daemon)   daemon_start ;;
    daemon-stop) daemon_stop ;;
    daemon-status) daemon_status ;;
    _monitor) monitor_loop ;;
    *)
        echo "用法: $0 {start|stop|status|restart|daemon|daemon-stop|daemon-status}"
        echo ""
        echo "  start         启动 Bot"
        echo "  stop          停止 Bot"
        echo "  status        查看状态"
        echo "  restart       重启"
        echo "  daemon        启动 + 守护（自动重启）"
        echo "  daemon-stop   停止守护 + Bot"
        echo "  daemon-status 查看守护进程和 Bot 状态"
        exit 1
        ;;
esac
