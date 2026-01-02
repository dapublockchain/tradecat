#!/usr/bin/env bash
# trading-service 启动/守护一体脚本
# 用法: ./scripts/start.sh {start|stop|status|daemon|once}

set -uo pipefail

# ==================== 配置区 ====================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
RUN_DIR="$SERVICE_DIR/pids"
LOG_DIR="$SERVICE_DIR/logs"
DAEMON_PID="$RUN_DIR/daemon.pid"
DAEMON_LOG="$LOG_DIR/daemon.log"
SERVICE_PID="$RUN_DIR/service.pid"
SERVICE_LOG="$LOG_DIR/service.log"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"
STOP_TIMEOUT=10

# 加载环境变量
if [ -f "$SERVICE_DIR/config/.env" ]; then
    set -a
    source "$SERVICE_DIR/config/.env"
    set +a
fi

# 启动命令 (MODE: simple/listener)
MODE="${MODE:-simple}"
START_CMD="python3 -u src/simple_scheduler.py"
[ "$MODE" = "listener" ] && START_CMD="python3 -u src/kline_listener.py"

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
        echo "服务已运行 (PID: $pid)"
        return 0
    fi
    
    cd "$SERVICE_DIR"
    source .venv/bin/activate
    PYTHONPATH=src nohup $START_CMD >> "$SERVICE_LOG" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$SERVICE_PID"
    
    sleep 1
    if is_running "$new_pid"; then
        log "START 服务 (PID: $new_pid, MODE: $MODE)"
        echo "✓ 服务已启动 (PID: $new_pid, MODE: $MODE)"
        return 0
    else
        log "ERROR 服务启动失败"
        echo "✗ 服务启动失败"
        rm -f "$SERVICE_PID"
        return 1
    fi
}

stop_service() {
    local pid=$(read_pid "$SERVICE_PID")
    
    if ! is_running "$pid"; then
        rm -f "$SERVICE_PID"
        echo "服务未运行"
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
        log "KILL 服务 (PID: $pid) 强制终止"
    else
        log "STOP 服务 (PID: $pid)"
    fi
    
    rm -f "$SERVICE_PID"
    echo "✓ 服务已停止"
}

status_service() {
    local pid=$(read_pid "$SERVICE_PID")
    if is_running "$pid"; then
        local uptime=$(get_uptime "$pid")
        echo "✓ 服务运行中 (PID: $pid, 运行: $uptime)"
        echo ""
        echo "=== 最近日志 ==="
        tail -10 "$SERVICE_LOG" 2>/dev/null
    else
        [ -f "$SERVICE_PID" ] && rm -f "$SERVICE_PID"
        echo "✗ 服务未运行"
    fi
}

# ==================== 守护进程 ====================
monitor_loop() {
    log "=== 守护进程启动 (间隔: ${CHECK_INTERVAL}s) ==="
    while true; do
        local pid=$(read_pid "$SERVICE_PID")
        if ! is_running "$pid"; then
            [ -f "$SERVICE_PID" ] && rm -f "$SERVICE_PID"
            log "CHECK 服务未运行，重启..."
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

# ==================== 一次性计算 ====================
run_once() {
    echo "=== 一次性全量计算 ==="
    cd "$SERVICE_DIR"
    source .venv/bin/activate
    PYTHONPATH=src python3 -m indicator_service --intervals 1m,5m,15m,1h,4h,1d,1w
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
    once)     run_once ;;
    *)
        echo "用法: $0 {start|stop|status|restart|daemon|daemon-stop|daemon-status|once}"
        echo ""
        echo "  start         启动服务"
        echo "  stop          停止服务"
        echo "  status        查看状态"
        echo "  restart       重启"
        echo "  daemon        启动 + 守护（自动重启）"
        echo "  daemon-stop   停止守护 + 服务"
        echo "  daemon-status 查看守护进程和服务状态"
        echo "  once          一次性全量计算"
        echo ""
        echo "环境变量: MODE=simple(默认) 或 MODE=listener"
        exit 1
        ;;
esac
