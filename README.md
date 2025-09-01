# 城通网盘命令行下载工具

一个跨平台的城通网盘（CTfile）命令行下载工具，支持高速多线程下载。

## 特性

- ✅ 支持城通网盘链接下载
- ✅ 自动获取真实下载地址
- ✅ 内置 aria2c 高速下载器（64线程）
- ✅ 跨平台支持（Windows、Linux、多种架构）
- ✅ 自动文件名识别和解码
- ✅ 绿色免安装，单文件运行

## 致谢

感谢 [nekohy/ctfile-downloader](https://github.com/nekohy/ctfile-downloader) 项目提供的绕过城通网盘线程限制的方法。本工具默认使用该项目作者提供的API服务器。

## 下载

从 [Releases](https://github.com/ericwang2006/ctfile-cli/releases) 页面下载适合你系统的预编译版本

## 使用方法

### 基本用法

```bash
./ctfile-cli ctfile://<xtlink>
```

### 完整语法

```bash
ctfile-cli [选项] ctfile://<xtlink>
```

### 选项说明

- `-api string`: 指定API服务器URL（默认: `https://api.umpsa.top`）

### 使用示例

```bash
# 基本下载
./ctfile-cli ctfile://your_xtlink_here

# 使用自定义API服务器
./ctfile-cli -api https://your-api-server.com ctfile://your_xtlink_here
```

## 工作原理

1. 解析城通网盘链接，提取 `xtlink` 参数
2. 通过API服务器获取文件信息和下载密钥
3. 构造真实下载链接
4. 自动下载并安装 aria2c（如果不存在）
5. 使用 aria2c 进行64线程高速下载
6. 自动识别并设置正确的文件名

## 技术特点

- **自动依赖管理**: 程序会自动下载适合当前系统的 aria2c 二进制文件
- **高性能下载**: 使用 aria2c 实现64连接并发下载
- **智能文件名处理**: 自动从重定向URL中提取并解码文件名
- **跨平台兼容**: 支持 Windows、Linux 及多种 CPU 架构
- **绿色免安装**: 单个可执行文件，无需额外安装

## 编译方法

### 环境要求

- Go 1.16 或更高版本
- Linux 编译环境（推荐 Ubuntu/Debian）

### 1. 安装交叉编译工具

```bash
sudo apt-get update && sudo apt-get install -y \
	binutils-aarch64-linux-gnu \
	binutils-arm-linux-gnueabihf \
	binutils-mips-linux-gnu \
	binutils-mipsel-linux-gnu \
	binutils-mips64-linux-gnuabi64 \
	binutils-mips64el-linux-gnuabi64 \
	binutils-mingw-w64 \
	gcc-multilib \
	zip
```

### 2. 克隆项目

```bash
git clone <repository-url>
cd ctfile-cli
```

### 3. 执行编译

```bash
chmod +x build.sh
./build.sh
```

编译完成后，所有平台的压缩包将生成在 `dist/` 目录中。

## 故障排除

### 1. aria2c 下载失败

如果 aria2c 自动下载失败，可以手动下载对应平台的 aria2c 二进制文件，放在程序同目录下。

### 2. API 服务器连接失败

尝试使用 `-api` 参数指定其他可用的API服务器。

### 3. 文件下载中断


aria2c 支持断点续传，重新运行命令即可继续下载。

## 免责声明

本项目仅供学习交流使用，无任何盈利/售卖行为，请勿用于非法用途，否则后果自负
