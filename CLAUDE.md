# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

ctfile-cli 是一个跨平台的城通网盘（CTfile）命令行下载工具，使用 Go 语言开发。该工具通过 API 服务器获取真实下载地址，并使用 aria2c 实现高速多线程下载。

## 核心架构

### 主程序结构 (ctfile-cli.go)

单一 Go 文件包含所有功能：

- **主流程** (main): 命令行参数解析 → 确保 aria2c 存在 → 获取下载信息 → 调用 aria2c 下载
- **aria2c 管理** (ensureAria2c): 检测本地 aria2c → 根据 IP 位置选择下载源 → 自动下载和安装 aria2c
- **下载信息获取**: 通过 API 服务器获取文件 ID 和下载链接
- **文件名处理**: 从重定向 URL 中提取和解码真实文件名

### 关键功能模块

1. **aria2c 依赖管理** (ctfile-cli.go:166-269)
   - 自动检测系统架构（GOOS/GOARCH）
   - 根据用户 IP 位置智能选择下载源（中国大陆使用备用镜像）
   - macOS 使用专门的 aria2c 构建版本
   - 自动解压 tar.gz 并设置执行权限

2. **IP 地理位置检测** (ctfile-cli.go:465-526)
   - 调用多个免费 API 服务检测用户位置
   - 为中国大陆用户优先使用备用下载源

3. **文件下载流程**
   - 构造 API 请求获取 download_info JSON
   - 使用文件 ID 构造下载链接
   - 通过重定向 URL 提取文件名
   - 调用 aria2c 执行多线程下载

### 构建系统 (build.sh)

- **交叉编译**: 支持 12 个平台架构组合（Linux/Windows/macOS，x86/ARM/MIPS）
- **优化选项**: CGO_ENABLED=0, -ldflags "-s -w", -trimpath
- **Strip 处理**: 自动为不同架构选择合适的 strip 工具（macOS 除外）
- **压缩打包**: Windows 生成 zip，Linux/macOS 生成 tar.gz
- **输出**: 所有构建产物保存在 dist/ 目录

## 常用命令

### 开发测试
```bash
# 本地构建和测试
go build -o ctfile-cli ctfile-cli.go
./ctfile-cli ctfile://<xtlink>

# 指定自定义线程数
./ctfile-cli -threads 128 ctfile://<xtlink>

# 使用自定义 API 服务器
./ctfile-cli -api https://custom-api.com ctfile://<xtlink>
```

### 构建发布版本
```bash
# 构建所有平台的发布版本
chmod +x build.sh
./build.sh

# 发布产物在 dist/ 目录
```

### Go 工具链
```bash
# 格式化代码
go fmt ctfile-cli.go

# 静态检查
go vet ctfile-cli.go

# 查看可用的交叉编译目标
go tool dist list
```

## 技术要点

- **依赖**: 无外部 Go 依赖，仅使用标准库
- **运行时依赖**: aria2c（自动下载）
- **API 服务器**: 默认使用 https://api.umpsa.top，感谢 nekohy/ctfile-downloader 项目
- **下载线程**: 默认 64 线程，可通过 -threads 参数自定义
- **User-Agent**: 模拟 Chrome 浏览器避免被限制

## 架构决策

1. **单文件设计**: 所有代码集中在一个 Go 文件中，便于分发和维护
2. **自动依赖管理**: 程序自动下载和配置 aria2c，用户无需手动安装
3. **智能镜像选择**: 根据用户地理位置自动选择最快的下载源
4. **跨平台兼容**: 通过 runtime.GOOS/GOARCH 适配不同平台的差异
