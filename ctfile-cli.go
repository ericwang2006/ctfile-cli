package main

import (
	"archive/tar"
	"compress/gzip"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

const (
	UserAgent     = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36"
	DefaultAPIUrl = "https://api.umpsa.top"
	Aria2cBaseURL = "https://github.com/ericwang2006/aria2-static-build-binaries/releases/download/v25.8.30/"
)

// DownloadInfo 结构体用于解析JSON响应
type DownloadInfo struct {
	Key  string `json:"key"`
	Name string `json:"name"`
}

func main() {
	// 定义命令行参数
	var apiURL string
	flag.StringVar(&apiURL, "api", DefaultAPIUrl, "指定API服务器URL")

	// 解析命令行参数
	flag.Parse()

	// 获取非flag参数
	args := flag.Args()

	// 检查参数
	if len(args) < 1 {
		fmt.Printf("用法: %s [选项] ctfile://<xtlink>\n", os.Args[0])
		fmt.Println("选项:")
		flag.PrintDefaults()
		os.Exit(1)
	}

	// 提取 xtlink ID
	xtlink := strings.TrimPrefix(args[0], "ctfile://")
	if xtlink == args[0] {
		fmt.Println("错误: 链接格式不正确，应为 ctfile://<xtlink>")
		os.Exit(1)
	}

	// 确保aria2c存在
	aria2cPath, err := ensureAria2c()
	if err != nil {
		fmt.Printf("无法获取aria2c: %v\n", err)
		os.Exit(2)
	}

	// 获取 download_info JSON
	infoURL := fmt.Sprintf("%s/download_info?xtlink=%s", apiURL, xtlink)
	fmt.Printf("使用API服务器: %s\n", apiURL)

	client := &http.Client{}
	req, err := http.NewRequest("GET", infoURL, nil)
	if err != nil {
		fmt.Printf("创建请求失败: %v\n", err)
		os.Exit(2)
	}
	req.Header.Set("User-Agent", UserAgent)

	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("请求失败: %v\n", err)
		os.Exit(2)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("读取响应失败: %v\n", err)
		os.Exit(2)
	}

	// 解析JSON响应
	var downloadInfos []DownloadInfo
	err = json.Unmarshal(body, &downloadInfos)
	if err != nil {
		fmt.Printf("JSON解析失败: %v\n", err)
		os.Exit(2)
	}

	// 检查是否提取到有效的file_id
	if len(downloadInfos) == 0 || downloadInfos[0].Key == "" {
		fmt.Println("未找到有效的 file_id")
		os.Exit(2)
	}

	fileID := downloadInfos[0].Key
	// 构造下载链接
	downloadURL := fmt.Sprintf("%s/download?xtlink=%s&file_id=%s", apiURL, xtlink, fileID)
	fmt.Printf("下载链接：%s\n", downloadURL)

	// 获取重定向后的URL以提取文件名
	redirectURL, err := getRedirectURL(downloadURL)
	if err != nil {
		fmt.Printf("获取重定向URL失败: %v\n", err)
		os.Exit(2)
	}

	// 从重定向URL中提取文件名
	filename, err := extractFilename(redirectURL)
	if err != nil {
		fmt.Printf("提取文件名失败: %v\n", err)
		os.Exit(2)
	}

	// 调用 aria2c
	cmd := exec.Command(aria2cPath,
		"-o", filename,
		"-V",
		"-x64",
		"-s64",
		"--header=User-Agent: "+UserAgent,
		downloadURL)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err = cmd.Run()
	if err != nil {
		fmt.Printf("aria2c 执行失败: %v\n", err)
		os.Exit(2)
	}
}

// ensureAria2c 确保aria2c存在，如果不存在则下载安装
func ensureAria2c() (string, error) {
	// 获取程序所在目录
	executablePath, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("获取程序路径失败: %v", err)
	}
	
	scriptDir := filepath.Dir(executablePath)

	// 根据操作系统选择aria2c可执行文件
	var aria2cPath string
	var aria2cBinaryName string
	if runtime.GOOS == "windows" {
		aria2cBinaryName = "aria2c.exe"
		aria2cPath = filepath.Join(scriptDir, aria2cBinaryName)
	} else {
		aria2cBinaryName = "aria2c"
		aria2cPath = filepath.Join(scriptDir, aria2cBinaryName)
	}

	// 检查aria2c是否存在
	if _, err := os.Stat(aria2cPath); err == nil {
		fmt.Println("aria2c已存在")
		return aria2cPath, nil
	}

	// aria2c不存在，需要下载
	fmt.Println("aria2c不存在，正在下载...")

	// 构造下载文件名
	archiveName := getArchiveName()
	downloadURL := Aria2cBaseURL + archiveName

	// 下载压缩包到临时文件
	tempDir := os.TempDir()
	archivePath := filepath.Join(tempDir, archiveName)
	err = downloadFile(downloadURL, archivePath)
	if err != nil {
		return "", fmt.Errorf("下载aria2c失败: %v", err)
	}
	defer os.Remove(archivePath) // 确保清理临时文件

	fmt.Println("下载完成，正在解压...")

	// 解压文件并直接提取aria2c到程序目录
	err = extractAria2cFromTarGz(archivePath, scriptDir, aria2cBinaryName)
	if err != nil {
		return "", fmt.Errorf("解压失败: %v", err)
	}

	// Linux系统需要添加执行权限
	if runtime.GOOS != "windows" {
		err = os.Chmod(aria2cPath, 0755)
		if err != nil {
			return "", fmt.Errorf("设置执行权限失败: %v", err)
		}
	}

	fmt.Println("aria2c安装完成")
	return aria2cPath, nil
}

// extractAria2cFromTarGz 从tar.gz文件中提取aria2c可执行文件
func extractAria2cFromTarGz(src, destDir, binaryName string) error {
	file, err := os.Open(src)
	if err != nil {
		return err
	}
	defer file.Close()

	gzr, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		// 只处理常规文件
		if header.Typeflag != tar.TypeReg {
			continue
		}

		// 检查是否是aria2c可执行文件
		filename := filepath.Base(header.Name)
		if filename == binaryName {
			// 创建目标文件
			targetPath := filepath.Join(destDir, binaryName)
			f, err := os.OpenFile(targetPath, os.O_CREATE|os.O_RDWR|os.O_TRUNC, os.FileMode(header.Mode))
			if err != nil {
				return err
			}

			// 复制文件内容
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return err
			}
			f.Close()
			
			fmt.Printf("成功提取 %s 到 %s\n", binaryName, targetPath)
			return nil
		}
	}

	return fmt.Errorf("在压缩包中未找到 %s", binaryName)
}

// getArchiveName 根据当前系统架构获取对应的压缩包文件名
func getArchiveName() string {
	goos := runtime.GOOS
	goarch := runtime.GOARCH

	return fmt.Sprintf("aria2c_%s_%s.tar.gz", goos, goarch)
}

// downloadFile 下载文件
func downloadFile(url, filepath string) error {
	client := &http.Client{}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", UserAgent)

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("下载失败，状态码: %d", resp.StatusCode)
	}

	out, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, resp.Body)
	return err
}

// extractTarGz 解压tar.gz文件
func extractTarGz(src, dest string) error {
	file, err := os.Open(src)
	if err != nil {
		return err
	}
	defer file.Close()

	gzr, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)

	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		target := filepath.Join(dest, header.Name)

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0755); err != nil {
				return err
			}
		case tar.TypeReg:
			// 确保目录存在
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				return err
			}

			f, err := os.OpenFile(target, os.O_CREATE|os.O_RDWR, os.FileMode(header.Mode))
			if err != nil {
				return err
			}

			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return err
			}
			f.Close()
		}
	}

	return nil
}

// getRedirectURL 获取重定向后的URL
func getRedirectURL(downloadURL string) (string, error) {
	client := &http.Client{
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			// 允许最多5次重定向
			if len(via) >= 5 {
				return http.ErrUseLastResponse
			}
			return nil
		},
	}

	req, err := http.NewRequest("GET", downloadURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", UserAgent)
	req.Header.Set("Range", "bytes=0-0")

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	return resp.Request.URL.String(), nil
}

// extractFilename 从URL中提取并解码文件名
func extractFilename(redirectURL string) (string, error) {
	// 使用正则表达式提取 downname 参数
	re := regexp.MustCompile(`downname=([^&]*)`)
	matches := re.FindStringSubmatch(redirectURL)
	if len(matches) < 2 {
		return "download_file", nil // 默认文件名
	}

	encodedName := matches[1]

	// URL解码
	decodedName, err := url.QueryUnescape(encodedName)
	if err != nil {
		return encodedName, nil // 如果解码失败，返回原始名称
	}

	return decodedName, nil
}
