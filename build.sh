#!/bin/bash

echo "Starting cross-compilation for ctfile-cli..."
echo

# 设置Go编译参数以生成最小尺寸的二进制文件
export CGO_ENABLED=0
LDFLAGS="-s -w"
TRIMPATH="-trimpath"

# 创建输出目录
mkdir -p dist
mkdir -p temp

# 构建函数
build_target() {
    local goos=$1
    local goarch=$2
    local goarm=$3
    local output=$4
    local desc=$5
    
    echo "Building for $desc..."
    
    # 构建二进制文件到临时目录
    local temp_binary="temp/$output"
    
    if [ -n "$goarm" ]; then
        GOOS=$goos GOARCH=$goarch GOARM=$goarm go build $TRIMPATH -ldflags "$LDFLAGS" -o "$temp_binary" ctfile-cli.go
    else
        GOOS=$goos GOARCH=$goarch go build $TRIMPATH -ldflags "$LDFLAGS" -o "$temp_binary" ctfile-cli.go
    fi
    
    if [ $? -eq 0 ]; then
        echo "[OK] $desc build complete"
        
        # 压缩文件
        compress_binary "$goos" "$goarch" "$temp_binary" "$output" "$desc"
    else
        echo "Failed to build for $desc"
    fi
    echo
}

# Strip二进制文件函数
strip_binary() {
    local goos=$1
    local goarch=$2
    local binary_path=$3
    
    # 获取当前系统架构
    local host_os=$(go env GOOS)
    local host_arch=$(go env GOARCH)
    
    # 根据目标平台选择合适的strip工具
    local strip_cmd="strip"
    local use_cross_strip=false
    
    # 检查是否为交叉编译
    if [ "$goos" != "$host_os" ] || [ "$goarch" != "$host_arch" ]; then
        use_cross_strip=true
        case "$goos-$goarch" in
            "linux-arm")
                if command -v arm-linux-gnueabihf-strip >/dev/null 2>&1; then
                    strip_cmd="arm-linux-gnueabihf-strip"
                    use_cross_strip=false
                elif command -v arm-linux-gnu-strip >/dev/null 2>&1; then
                    strip_cmd="arm-linux-gnu-strip"
                    use_cross_strip=false
                fi
                ;;
            "linux-arm64")
                if command -v aarch64-linux-gnu-strip >/dev/null 2>&1; then
                    strip_cmd="aarch64-linux-gnu-strip"
                    use_cross_strip=false
                fi
                ;;
            "linux-mips")
                if command -v mips-linux-gnu-strip >/dev/null 2>&1; then
                    strip_cmd="mips-linux-gnu-strip"
                    use_cross_strip=false
                fi
                ;;
            "linux-mipsle")
                if command -v mipsel-linux-gnu-strip >/dev/null 2>&1; then
                    strip_cmd="mipsel-linux-gnu-strip"
                    use_cross_strip=false
                fi
                ;;
            "linux-mips64")
                if command -v mips64-linux-gnuabi64-strip >/dev/null 2>&1; then
                    strip_cmd="mips64-linux-gnuabi64-strip"
                    use_cross_strip=false
                elif command -v mips64-linux-gnu-strip >/dev/null 2>&1; then
                    strip_cmd="mips64-linux-gnu-strip"
                    use_cross_strip=false
                fi
                ;;
            "linux-mips64le")
                if command -v mips64el-linux-gnuabi64-strip >/dev/null 2>&1; then
                    strip_cmd="mips64el-linux-gnuabi64-strip"
                    use_cross_strip=false
                elif command -v mips64el-linux-gnu-strip >/dev/null 2>&1; then
                    strip_cmd="mips64el-linux-gnu-strip"
                    use_cross_strip=false
                fi
                ;;
            "linux-386")
                # i686 Linux (32位)
                if [ "$host_arch" = "amd64" ]; then
                    # 在64位系统上，通常可以直接用strip处理32位二进制
                    strip_cmd="strip"
                    use_cross_strip=false
                elif command -v i686-linux-gnu-strip >/dev/null 2>&1; then
                    strip_cmd="i686-linux-gnu-strip"
                    use_cross_strip=false
                fi
                ;;
            "linux-amd64")
                # x86_64 Linux
                if [ "$host_arch" = "amd64" ] || [ "$host_arch" = "386" ]; then
                    strip_cmd="strip"
                    use_cross_strip=false
                fi
                ;;
            "windows-amd64")
                if command -v x86_64-w64-mingw32-strip >/dev/null 2>&1; then
                    strip_cmd="x86_64-w64-mingw32-strip"
                    use_cross_strip=false
                fi
                ;;
            "windows-386")
                if command -v i686-w64-mingw32-strip >/dev/null 2>&1; then
                    strip_cmd="i686-w64-mingw32-strip"
                    use_cross_strip=false
                fi
                ;;
        esac
    else
        use_cross_strip=false
    fi
    
    # 如果是交叉编译但没有找到对应的strip工具，跳过strip
    if [ "$use_cross_strip" = true ]; then
        echo "  [INFO] Cross-compilation detected ($host_os/$host_arch -> $goos/$goarch)"
        echo "  [INFO] No cross-strip tool found for $goos/$goarch, skipping strip"
        echo "  [TIP] Install cross-compilation tools:"
        echo "        # For ARM architectures:"
        echo "        sudo apt-get install binutils-aarch64-linux-gnu binutils-arm-linux-gnueabihf"
        echo "        # For MIPS architectures:"
        echo "        sudo apt-get install binutils-mips-linux-gnu binutils-mipsel-linux-gnu"
        echo "        sudo apt-get install binutils-mips64-linux-gnuabi64 binutils-mips64el-linux-gnuabi64"
        echo "        # For Windows cross-compilation:"
        echo "        sudo apt-get install binutils-mingw-w64"
        echo "        # For i686 (32-bit) support:"
        echo "        sudo apt-get install gcc-multilib"
        return 0
    fi
    
    # 执行strip命令
    if command -v "$strip_cmd" >/dev/null 2>&1; then
        echo "  Stripping with $strip_cmd..."
        local strip_output
        strip_output=$("$strip_cmd" "$binary_path" 2>&1)
        local strip_result=$?
        
        if [ $strip_result -eq 0 ]; then
            echo "  [OK] Binary stripped successfully"
        else
            echo "  [WARN] Strip failed: $strip_output"
            echo "  [INFO] Continuing with unstripped binary"
        fi
    else
        echo "  [INFO] Strip command '$strip_cmd' not available"
    fi
}

# 压缩函数
compress_binary() {
    local goos=$1
    local goarch=$2
    local temp_binary=$3
    local original_name=$4
    local desc=$5
    
    # Strip二进制文件
    strip_binary "$goos" "$goarch" "$temp_binary"
    
    # 获取当前工作目录的绝对路径
    local work_dir=$(pwd)
    
    # 创建临时目录用于压缩
    local compress_dir="temp/compress_$(basename "$original_name")"
    mkdir -p "$compress_dir"
    
    if [ "$goos" = "windows" ]; then
        # Windows系统：压缩成zip，内部文件名为ctfile-cli.exe
        local inner_name="ctfile-cli.exe"
        cp "$temp_binary" "$compress_dir/$inner_name"
        
        # 生成压缩包名称（去掉原始.exe后缀）
        local archive_name="${original_name%.exe}.zip"
        local archive_path="$work_dir/dist/$archive_name"
        
        echo "Compressing $desc to $archive_name..."
        (cd "$compress_dir" && zip -q "$archive_path" "$inner_name")
        
        if [ $? -eq 0 ]; then
            echo "[OK] $desc compressed to $archive_name"
        else
            echo "Failed to compress $desc"
        fi
    else
        # Linux系统：压缩成tar.gz，内部文件名为ctfile-cli
        local inner_name="ctfile-cli"
        cp "$temp_binary" "$compress_dir/$inner_name"
        
        local archive_name="${original_name}.tar.gz"
        local archive_path="$work_dir/dist/$archive_name"
        
        echo "Compressing $desc to $archive_name..."
        (cd "$compress_dir" && tar -czf "$archive_path" "$inner_name")
        
        if [ $? -eq 0 ]; then
            echo "[OK] $desc compressed to $archive_name"
        else
            echo "Failed to compress $desc"
        fi
    fi
    
    # 清理临时压缩目录
    rm -rf "$compress_dir"
}

# 构建所有目标平台
build_target "linux" "arm" "7" "ctfile-cli_linux_arm" "ARM Linux"
build_target "linux" "arm64" "" "ctfile-cli_linux_arm64" "ARM64 Linux"
build_target "linux" "mips" "" "ctfile-cli_linux_mips" "MIPS Linux"
build_target "linux" "mipsle" "" "ctfile-cli_linux_mipsle" "MIPSEL Linux"
build_target "linux" "mips64" "" "ctfile-cli_linux_mips64" "MIPS64 Linux"
build_target "linux" "mips64le" "" "ctfile-cli_linux_mips64le" "MIPS64EL Linux"
build_target "linux" "amd64" "" "ctfile-cli_linux_amd64" "x86_64 Linux"
build_target "linux" "386" "" "ctfile-cli_linux_386" "i686 Linux"
build_target "windows" "amd64" "" "ctfile-cli_windows_amd64.exe" "x86_64 Windows"
build_target "windows" "386" "" "ctfile-cli_windows_386.exe" "i686 Windows"

# 清理临时目录
rm -rf temp

echo "All builds completed and compressed. Check the 'dist' directory for archive files."