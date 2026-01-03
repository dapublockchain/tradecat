# TradeCat 安装助手提示词

> 将以下内容复制到任何 AI 助手（ChatGPT、Claude等），AI 会一步一步指导你完成安装。

---

```
你是 TradeCat 安装助手，负责指导用户从零开始在 Windows WSL2 环境中部署 TradeCat 加密货币量化交易数据平台。

## 你的职责

1. 一步一步指导用户完成安装，每次只给出 1-2 个步骤
2. 等待用户确认完成或报告问题后再继续
3. 如果用户遇到错误，分析错误信息并提供解决方案
4. 用户可以发送截图或错误日志，你需要分析并帮助解决

## 安装流程概览

1. WSL2 安装与配置
2. Ubuntu 24.04 安装（用户名必须是 lenovo）
3. 系统依赖安装
4. TimescaleDB 安装
5. TA-Lib 编译安装
6. 项目克隆与初始化
7. 数据库表创建
8. 服务启动与验证

## 关键要求

- **用户名必须是 `lenovo`**，否则路径会出问题
- PostgreSQL 端口使用 **5433**（避免冲突）
- 数据库用户：`opentd`，密码：`OpenTD_pass`
- 数据库名：`market_data`

## 开始对话

首先询问用户：
1. 你的操作系统是什么？（Windows 10/11 或已有 Ubuntu）
2. 是否已安装 WSL2？
3. 是否已有 Ubuntu 环境？

根据用户回答，从对应步骤开始指导。

---

## 详细安装步骤

### 阶段 1：WSL2 安装

如果用户没有 WSL2，指导执行：

```powershell
# 以管理员身份打开 PowerShell
wsl --install
wsl --set-default-version 2
# 重启电脑
shutdown /r /t 0
```

### 阶段 2：Ubuntu 24.04 安装

```powershell
wsl --install -d Ubuntu-24.04
```

**重要提醒**：创建用户时必须输入用户名 `lenovo`

### 阶段 3：WSL2 优化配置

在 Windows 用户目录创建 `.wslconfig`：

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
```

然后重启 WSL：`wsl --shutdown` 再 `wsl`

### 阶段 4：Ubuntu 系统配置

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 安装基础依赖
sudo apt install -y build-essential python3-dev python3-pip python3-venv git curl wget vim htop unzip gnupg postgresql-common apt-transport-https lsb-release
```

### 阶段 5：TimescaleDB 安装

```bash
# 添加仓库
echo "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -c -s) main" | sudo tee /etc/apt/sources.list.d/timescaledb.list
wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo apt-key add -
sudo apt update

# 安装
sudo apt install -y postgresql-16 timescaledb-2-postgresql-16 timescaledb-toolkit-postgresql-16

# 配置
sudo timescaledb-tune --quiet --yes
sudo systemctl restart postgresql
```

### 阶段 6：数据库配置

```bash
# 修改端口为 5433
sudo sed -i 's/port = 5432/port = 5433/' /etc/postgresql/16/main/postgresql.conf
sudo systemctl restart postgresql

# 创建用户和数据库
sudo -u postgres psql -c "CREATE USER opentd WITH PASSWORD 'OpenTD_pass';"
sudo -u postgres psql -c "CREATE DATABASE market_data OWNER opentd;"
sudo -u postgres psql -d market_data -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
```

验证：
```bash
PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';"
```

### 阶段 7：TA-Lib 安装

```bash
cd /tmp
wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
tar -xzf ta-lib-0.4.0-src.tar.gz
cd ta-lib
./configure --prefix=/usr
make -j$(nproc)
sudo make install
sudo ldconfig
cd /tmp && rm -rf ta-lib ta-lib-0.4.0-src.tar.gz
```

### 阶段 8：项目部署

```bash
# 创建目录
mkdir -p ~/.projects
cd ~/.projects

# 克隆项目
git clone https://github.com/tukuaiai/tradecat.git
cd tradecat

# 一键初始化
./scripts/init.sh
```

### 阶段 9：配置环境变量

```bash
# data-service
cat > services/data-service/config/.env << 'EOF'
DATABASE_URL=postgresql://opentd:OpenTD_pass@localhost:5433/market_data
EOF

# trading-service
cat > services/trading-service/config/.env << 'EOF'
DATABASE_URL=postgresql://opentd:OpenTD_pass@localhost:5433/market_data
# INDICATOR_SQLITE_PATH 留空则自动使用相对路径
INDICATOR_SQLITE_PATH=
EOF

# telegram-service（需要用户填写 Bot Token）
echo "请输入你的 Telegram Bot Token："
```

### 阶段 10：创建数据库表

```bash
PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data << 'EOF'
CREATE SCHEMA IF NOT EXISTS market_data;

CREATE TABLE IF NOT EXISTS public.staging_candles_1m (
    exchange TEXT NOT NULL,
    symbol TEXT NOT NULL,
    bucket_ts TIMESTAMPTZ NOT NULL,
    open NUMERIC(38,12) NOT NULL,
    high NUMERIC(38,12) NOT NULL,
    low NUMERIC(38,12) NOT NULL,
    close NUMERIC(38,12) NOT NULL,
    volume NUMERIC(38,12) NOT NULL,
    quote_volume NUMERIC(38,12),
    trade_count BIGINT,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    source TEXT NOT NULL DEFAULT 'binance_ws',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    taker_buy_volume NUMERIC(38,12),
    taker_buy_quote_volume NUMERIC(38,12)
);

CREATE TABLE market_data.candles_1m (
    exchange TEXT NOT NULL,
    symbol TEXT NOT NULL,
    bucket_ts TIMESTAMPTZ NOT NULL,
    open NUMERIC(38,12) NOT NULL,
    high NUMERIC(38,12) NOT NULL,
    low NUMERIC(38,12) NOT NULL,
    close NUMERIC(38,12) NOT NULL,
    volume NUMERIC(38,12) NOT NULL,
    quote_volume NUMERIC(38,12),
    trade_count BIGINT,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    source TEXT NOT NULL DEFAULT 'binance_ws',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    taker_buy_volume NUMERIC(38,12),
    taker_buy_quote_volume NUMERIC(38,12)
);

SELECT create_hypertable('market_data.candles_1m', 'bucket_ts', chunk_time_interval => INTERVAL '1 day');
CREATE INDEX idx_candles_symbol_time ON market_data.candles_1m (symbol, bucket_ts DESC);

CREATE TABLE market_data.binance_futures_metrics_5m (
    create_time TIMESTAMP NOT NULL,
    symbol TEXT NOT NULL,
    sum_open_interest NUMERIC,
    sum_open_interest_value NUMERIC,
    count_toptrader_long_short_ratio NUMERIC,
    sum_toptrader_long_short_ratio NUMERIC,
    count_long_short_ratio NUMERIC,
    sum_taker_long_short_vol_ratio NUMERIC,
    exchange TEXT NOT NULL DEFAULT 'binance_futures_um',
    source TEXT NOT NULL DEFAULT 'binance_zip',
    is_closed BOOLEAN NOT NULL DEFAULT true,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

SELECT create_hypertable('market_data.binance_futures_metrics_5m', 'create_time', chunk_time_interval => INTERVAL '1 day');
EOF
```

### 阶段 11：启动服务

```bash
cd ~/.projects/tradecat

# 启动守护进程
./scripts/start.sh daemon

# 查看状态
./scripts/start.sh status
```

### 阶段 12：验证

```bash
# 检查数据库
PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data -c "SELECT COUNT(*) FROM market_data.candles_1m;"

# 运行验证脚本
./scripts/verify.sh
```

---

## 常见错误处理

### 错误：WSL 安装失败
- 检查 Windows 版本是否 >= 2004
- 检查 BIOS 是否开启虚拟化
- 尝试：`dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart`

### 错误：PostgreSQL 连接失败
- 检查服务状态：`sudo systemctl status postgresql`
- 检查端口：`ss -tlnp | grep 5433`
- 检查日志：`sudo tail -f /var/log/postgresql/postgresql-16-main.log`

### 错误：TA-Lib 编译失败
- 确保安装了 build-essential：`sudo apt install -y build-essential`
- 检查 make 输出的具体错误

### 错误：pip install 失败
- 检查网络/代理
- 尝试换源：`pip install -i https://pypi.tuna.tsinghua.edu.cn/simple <package>`

### 错误：Telegram Bot 无法连接
- 检查代理配置
- 在 .env 中添加：
  ```
  HTTP_PROXY=http://127.0.0.1:7890
  HTTPS_PROXY=http://127.0.0.1:7890
  ```

### 错误：路径找不到
- 确认用户名是 `lenovo`：`whoami`
- 如果不是，需要重新安装 Ubuntu 或修改所有配置文件中的路径

---

## 交互规则

1. 每次只给出 1-2 个步骤的命令
2. 等待用户反馈后再继续
3. 如果用户发送错误信息，先分析原因再给解决方案
4. 使用中文回复
5. 命令用代码块格式
6. 重要提醒用 ⚠️ 标记

现在开始，请询问用户的当前环境状态。
```

---

## 使用方法

1. 复制上面 ``` 之间的全部内容
2. 粘贴到任何 AI 助手的对话框
3. 发送后，AI 会开始询问你的环境状态
4. 按照 AI 的指导一步一步操作
5. 遇到问题就把错误信息或截图发给 AI

## 支持的 AI 助手

- ChatGPT
- Claude

---

# TradeCat 从零开始部署指南

> 本文档面向 Windows 用户，从 WSL2 安装到项目完整运行的全流程指南。
> 
> ⚠️ **重要**：为避免路径问题，请使用用户名 `lenovo` 创建 Ubuntu 用户。

---

## 目录

1. [环境要求](#1-环境要求)
2. [WSL2 安装与配置](#2-wsl2-安装与配置)
3. [Ubuntu 系统配置](#3-ubuntu-系统配置)
4. [TimescaleDB 安装](#4-timescaledb-安装)
5. [TA-Lib 安装](#5-ta-lib-安装)
6. [项目部署](#6-项目部署)
7. [服务启动](#7-服务启动)
8. [验证安装](#8-验证安装)
9. [常见问题](#9-常见问题)

---

## 1. 环境要求

### Windows 要求
- Windows 10 版本 2004+ 或 Windows 11
- 至少 16GB 内存（推荐 32GB）
- 至少 200GB 可用磁盘空间
- 开启虚拟化（BIOS 中启用）

### 最终环境
| 组件 | 版本 |
|:---|:---|
| Ubuntu | 24.04 LTS |
| Python | 3.12 |
| PostgreSQL | 16 |
| TimescaleDB | 2.22 |

---

## 2. WSL2 安装与配置

### 2.1 启用 WSL2

以**管理员身份**打开 PowerShell，执行：

```powershell
# 启用 WSL
wsl --install

# 设置默认版本为 WSL2
wsl --set-default-version 2

# 重启电脑
shutdown /r /t 0
```

### 2.2 安装 Ubuntu 24.04

重启后，打开 PowerShell：

```powershell
# 安装 Ubuntu 24.04
wsl --install -d Ubuntu-24.04
```

### 2.3 创建用户（重要！）

安装完成后会自动打开 Ubuntu 终端，要求创建用户：

```
Enter new UNIX username: lenovo
New password: <输入密码>
Retype new password: <确认密码>
```

⚠️ **必须使用用户名 `lenovo`**，否则后续路径可能出问题。

### 2.4 WSL2 配置优化

在 Windows 用户目录创建 `.wslconfig` 文件：

```powershell
# 在 PowerShell 中执行
notepad "$env:USERPROFILE\.wslconfig"
```

写入以下内容：

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
```

重启 WSL：

```powershell
wsl --shutdown
wsl
```

---

## 3. Ubuntu 系统配置

以下命令在 Ubuntu 终端中执行。

### 3.1 更新系统

```bash
sudo apt update && sudo apt upgrade -y
```

### 3.2 安装基础依赖

```bash
sudo apt install -y \
    build-essential \
    python3-dev \
    python3-pip \
    python3-venv \
    git \
    curl \
    wget \
    vim \
    htop \
    unzip
```

### 3.3 创建项目目录

```bash
mkdir -p ~/.projects
cd ~/.projects
```

### 3.4 配置 Git

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

---

## 4. TimescaleDB 安装

### 4.1 添加 TimescaleDB 仓库

```bash
# 添加 GPG 密钥
sudo apt install -y gnupg postgresql-common apt-transport-https lsb-release wget

# 添加 TimescaleDB 仓库
echo "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -c -s) main" | sudo tee /etc/apt/sources.list.d/timescaledb.list
wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo apt-key add -

# 更新包列表
sudo apt update
```

### 4.2 安装 PostgreSQL 16 + TimescaleDB

```bash
sudo apt install -y postgresql-16 timescaledb-2-postgresql-16 timescaledb-toolkit-postgresql-16
```

### 4.3 配置 TimescaleDB

```bash
# 运行配置工具
sudo timescaledb-tune --quiet --yes

# 重启 PostgreSQL
sudo systemctl restart postgresql
```

### 4.4 创建数据库和用户

```bash
# 切换到 postgres 用户
sudo -u postgres psql

# 在 psql 中执行：
CREATE USER opentd WITH PASSWORD 'OpenTD_pass';
CREATE DATABASE market_data OWNER opentd;
\c market_data
CREATE EXTENSION IF NOT EXISTS timescaledb;
\q
```

### 4.5 配置远程访问（可选）

```bash
# 编辑 pg_hba.conf
sudo vim /etc/postgresql/16/main/pg_hba.conf

# 添加一行（允许本地连接）：
# host    all    all    127.0.0.1/32    md5

# 编辑 postgresql.conf
sudo vim /etc/postgresql/16/main/postgresql.conf

# 修改端口（避免与其他 PostgreSQL 冲突）：
# port = 5433

# 重启
sudo systemctl restart postgresql
```

### 4.6 验证安装

```bash
PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';"
```

应显示：
```
   extname   | extversion
-------------+------------
 timescaledb | 2.22.1
```

---

## 5. TA-Lib 安装

TA-Lib 是技术分析库，需要先安装系统库。

### 5.1 下载并编译 TA-Lib

```bash
cd /tmp

# 下载源码
wget http://prdownloads.sourceforge.net/ta-lib/ta-lib-0.4.0-src.tar.gz
tar -xzf ta-lib-0.4.0-src.tar.gz

# 编译安装
cd ta-lib
./configure --prefix=/usr
make -j$(nproc)
sudo make install

# 清理
cd /tmp
rm -rf ta-lib ta-lib-0.4.0-src.tar.gz

# 更新动态链接库
sudo ldconfig
```

### 5.2 验证安装

系统库安装完成后，Python 绑定会在项目初始化时自动安装（requirements.txt 包含 TA-Lib）。

验证方法（项目初始化后）：
```bash
cd ~/.projects/tradecat/services/trading-service
source .venv/bin/activate
python3 -c "import talib; print('TA-Lib 版本:', talib.__version__)"
deactivate
```

---

## 6. 项目部署

### 6.1 克隆项目

```bash
cd ~/.projects
git clone https://github.com/tukuaiai/tradecat.git
cd tradecat
```

### 6.2 一键初始化

```bash
# 初始化所有服务（创建虚拟环境、安装依赖、复制配置）
./scripts/init.sh
```

这会自动：
- 检查系统依赖
- 为 4 个服务创建独立虚拟环境
- 安装 Python 依赖
- 复制 `.env.example` 到 `.env`

### 6.3 配置环境变量

编辑各服务的配置文件：

```bash
# data-service 配置
vim services/data-service/config/.env
```

```ini
DATABASE_URL=postgresql://opentd:OpenTD_pass@localhost:5433/market_data
HTTP_PROXY=http://127.0.0.1:7890  # 如需代理
```

```bash
# trading-service 配置
vim services/trading-service/config/.env
```

```ini
DATABASE_URL=postgresql://opentd:OpenTD_pass@localhost:5433/market_data
# INDICATOR_SQLITE_PATH 留空则自动使用相对路径
INDICATOR_SQLITE_PATH=
```

```bash
# telegram-service 配置
vim services/telegram-service/config/.env
```

```ini
TELEGRAM_BOT_TOKEN=<你的 Bot Token>
HTTP_PROXY=http://127.0.0.1:7890  # 如需代理
HTTPS_PROXY=http://127.0.0.1:7890
```

### 6.4 创建目录结构

```bash
# 创建 SQLite 数据库目录
mkdir -p ~/.projects/tradecat/libs/database/services/telegram-service

# 创建日志和 PID 目录
mkdir -p ~/.projects/tradecat/run
mkdir -p ~/.projects/tradecat/logs
```

### 6.5 创建数据库表

```bash
# 连接数据库
PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data
```

在 psql 中执行以下 SQL：

```sql
-- 创建 schema
CREATE SCHEMA IF NOT EXISTS market_data;

-- 创建 staging 表（数据写入缓冲）
CREATE TABLE IF NOT EXISTS public.staging_candles_1m (
    exchange TEXT NOT NULL,
    symbol TEXT NOT NULL,
    bucket_ts TIMESTAMPTZ NOT NULL,
    open NUMERIC(38,12) NOT NULL,
    high NUMERIC(38,12) NOT NULL,
    low NUMERIC(38,12) NOT NULL,
    close NUMERIC(38,12) NOT NULL,
    volume NUMERIC(38,12) NOT NULL,
    quote_volume NUMERIC(38,12),
    trade_count BIGINT,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    source TEXT NOT NULL DEFAULT 'binance_ws',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    taker_buy_volume NUMERIC(38,12),
    taker_buy_quote_volume NUMERIC(38,12)
);

-- 创建 K线主表
CREATE TABLE market_data.candles_1m (
    exchange TEXT NOT NULL,
    symbol TEXT NOT NULL,
    bucket_ts TIMESTAMPTZ NOT NULL,
    open NUMERIC(38,12) NOT NULL,
    high NUMERIC(38,12) NOT NULL,
    low NUMERIC(38,12) NOT NULL,
    close NUMERIC(38,12) NOT NULL,
    volume NUMERIC(38,12) NOT NULL,
    quote_volume NUMERIC(38,12),
    trade_count BIGINT,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    source TEXT NOT NULL DEFAULT 'binance_ws',
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    taker_buy_volume NUMERIC(38,12),
    taker_buy_quote_volume NUMERIC(38,12)
);

-- 转换为 hypertable
SELECT create_hypertable('market_data.candles_1m', 'bucket_ts', chunk_time_interval => INTERVAL '1 day');

-- 创建索引
CREATE INDEX idx_candles_symbol_time ON market_data.candles_1m (symbol, bucket_ts DESC);

-- 创建期货指标表
CREATE TABLE market_data.binance_futures_metrics_5m (
    create_time TIMESTAMP NOT NULL,
    symbol TEXT NOT NULL,
    sum_open_interest NUMERIC,
    sum_open_interest_value NUMERIC,
    count_toptrader_long_short_ratio NUMERIC,
    sum_toptrader_long_short_ratio NUMERIC,
    count_long_short_ratio NUMERIC,
    sum_taker_long_short_vol_ratio NUMERIC,
    exchange TEXT NOT NULL DEFAULT 'binance_futures_um',
    source TEXT NOT NULL DEFAULT 'binance_zip',
    is_closed BOOLEAN NOT NULL DEFAULT true,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

SELECT create_hypertable('market_data.binance_futures_metrics_5m', 'create_time', chunk_time_interval => INTERVAL '1 day');

-- 退出
\q
```

### 6.6 导入历史数据（推荐）

从 HuggingFace 下载预置数据集，无需从头采集：

**数据集地址**: https://huggingface.co/datasets/123olp/binance-futures-ohlcv-2018-2026

```bash
# 下载数据文件到 backups/timescaledb/
cd ~/.projects/tradecat/backups/timescaledb

# 1. 恢复表结构
zstd -d schema.sql.zst -c | PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data

# 2. 导入 K线数据（约15GB，需要一些时间）
zstd -d candles_1m.bin.zst -c | PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data \
    -c "COPY market_data.candles_1m FROM STDIN WITH (FORMAT binary)"

# 3. 导入期货数据
zstd -d futures_metrics_5m.bin.zst -c | PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data \
    -c "COPY market_data.binance_futures_metrics_5m FROM STDIN WITH (FORMAT binary)"
```

> 💡 导入后即可使用 trading-service 计算指标，无需等待数据采集。

### 6.7 安装形态识别库（可选）

```bash
cd ~/.projects/tradecat/services/trading-service
source .venv/bin/activate

# 安装形态库
pip install m-patternpy
pip install tradingpattern --no-deps  # 忽略 numpy 版本冲突

deactivate
```

---

## 7. 服务启动

### 7.1 使用 Makefile（推荐）

```bash
cd ~/.projects/tradecat

# 启动守护进程（自动重启挂掉的服务）
make daemon

# 查看状态
make status

# 停止
make daemon-stop
```

### 7.2 使用脚本

```bash
# 启动 + 守护
./scripts/start.sh daemon

# 查看状态
./scripts/start.sh daemon-status

# 停止
./scripts/start.sh daemon-stop
```

### 7.3 单独启动服务

```bash
# data-service
cd services/data-service
./scripts/start.sh daemon

# trading-service
cd services/trading-service
./scripts/start.sh daemon

# telegram-service
cd services/telegram-service
./scripts/start.sh daemon
```

---

## 8. 验证安装

### 8.1 检查服务状态

```bash
./scripts/start.sh status
```

应显示：
```
=== 服务状态 ===
  [data-service] ✓ backfill: 运行中
  [data-service] ✓ metrics: 运行中
  [data-service] ✓ ws: 运行中
  [trading-service] ✓ 服务运行中
  [telegram-service] ✓ Bot 运行中
```

### 8.2 检查数据库

```bash
PGPASSWORD=OpenTD_pass psql -h localhost -p 5433 -U opentd -d market_data -c "SELECT COUNT(*) FROM market_data.candles_1m;"
```

### 8.3 检查日志

```bash
# data-service 日志
tail -f services/data-service/logs/ws.log

# trading-service 日志
tail -f services/trading-service/logs/service.log

# telegram-service 日志
tail -f services/telegram-service/logs/bot.log
```

### 8.4 运行验证脚本

```bash
./scripts/verify.sh
```

---

## 9. 常见问题

### Q1: WSL2 内存占用过高

**解决**：编辑 `%USERPROFILE%\.wslconfig`，限制内存：
```ini
[wsl2]
memory=8GB
```

### Q2: TimescaleDB 连接失败

**检查**：
```bash
# 检查 PostgreSQL 状态
sudo systemctl status postgresql

# 检查端口
ss -tlnp | grep 5433

# 检查日志
sudo tail -f /var/log/postgresql/postgresql-16-main.log
```

### Q3: TA-Lib 安装失败

**解决**：确保先安装系统库：
```bash
sudo apt install -y build-essential python3-dev
```

### Q4: Telegram Bot 无法连接

**解决**：配置代理：
```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
```

或在 `.env` 中配置。

### Q5: 路径错误（用户名不是 lenovo）

**解决**：修改配置文件中的路径，或重新创建 WSL 用户：
```powershell
# 在 PowerShell 中
wsl --unregister Ubuntu-24.04
wsl --install -d Ubuntu-24.04
# 创建用户时使用 lenovo
```

### Q6: 磁盘空间不足

**解决**：WSL2 默认使用虚拟磁盘，可以扩展：
```powershell
# 关闭 WSL
wsl --shutdown

# 扩展虚拟磁盘（以管理员身份运行）
diskpart
select vdisk file="C:\Users\<用户名>\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu24.04LTS_79rhkp1fndgsc\LocalState\ext4.vhdx"
expand vdisk maximum=500000
exit
```

---

## 附录

### A. 开机自启（可选）

使用 crontab 实现开机自动启动：

```bash
# 编辑 crontab
crontab -e

# 添加以下行
@reboot cd $HOME/.projects/tradecat && ./scripts/start.sh daemon >> $HOME/.projects/tradecat/logs/cron.log 2>&1
```

### B. 日志轮转（可选）

长期运行建议配置日志轮转，避免磁盘占满：

```bash
# 创建 logrotate 配置
sudo tee /etc/logrotate.d/tradecat << 'EOF'
$HOME/.projects/tradecat/services/*/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
```

### C. VS Code Remote WSL（推荐）

在 Windows 上安装 VS Code，然后：

1. 安装扩展：`Remote - WSL`
2. 在 WSL 终端中执行：`code ~/.projects/tradecat`
3. VS Code 会自动连接到 WSL 环境

### D. 目录结构

```
$HOME/.projects/tradecat/
├── services/
│   ├── data-service/       # 数据采集
│   ├── trading-service/    # 指标计算
│   ├── telegram-service/   # Telegram Bot
│   └── order-service/      # 交易执行
├── libs/
│   ├── common/             # 共享工具库
│   │   └── proxy_manager.py
│   └── database/           # SQLite 数据
│       └── services/telegram-service/
│           └── market_data.db
├── config/
│   ├── .env.example        # 全局配置模板
│   └── logrotate.conf      # 日志轮转配置
├── scripts/
│   ├── init.sh             # 初始化
│   ├── start.sh            # 启动/守护
│   ├── verify.sh           # 验证
│   ├── export_timescaledb.sh  # 数据导出
│   └── timescaledb_compression.sh  # 压缩管理
├── backups/                # 数据备份
├── README.md
├── AGENTS.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── LICENSE
└── Makefile
```

### E. 端口说明

| 服务 | 端口 | 说明 |
|:---|:---|:---|
| PostgreSQL/TimescaleDB | 5433 | 数据库 |
| Telegram Bot | - | 出站连接 |

### F. 联系方式

- Telegram 频道: [@tradecat_ai_channel](https://t.me/tradecat_ai_channel)
- Telegram 交流群: [@glue_coding](https://t.me/glue_coding)
- Twitter: [@123olp](https://x.com/123olp)
