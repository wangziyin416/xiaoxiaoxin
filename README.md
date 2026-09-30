# 小小信

![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Release](https://img.shields.io/github/v/release/wangziyin416/xiaoxiaoxin?display_name=tag)

一个以 A 股行情为主、适合放在桌面角落的迷你行情宠物。

> 项目仍处于早期测试阶段。行情可能延迟或中断，内容仅供学习与信息展示，不构成投资建议。

## 下载

前往 [Releases](https://github.com/wangziyin416/xiaoxiaoxin/releases/latest) 下载对应平台版本：

- `小小信-macOS.zip`：macOS 13 及以上，当前面向 Apple Silicon。
- `小小信-Windows-x64.zip`：Windows 10/11 64 位免安装版。

## 运行 macOS 桌面版

首次构建：

```bash
chmod +x build-macos.sh
./build-macos.sh
open dist/小小信.app
```

收起后为 `120 × 56` 的纯股价窗口，展开后为 `200 × 200` 的迷你行情窗口。

## 运行 Windows 桌面版

从 GitHub Releases 下载 `小小信-Windows-x64.zip`，完整解压后双击 `小小信.exe`。程序是免安装便携版，并自带 .NET 运行时。

- 支持 Windows 10/11 64 位系统。
- 电脑需要安装 Microsoft Edge WebView2 Runtime；Windows 10/11 通常已经预装。
- 老板键为 `Ctrl + Shift + H`，也可以通过系统托盘图标显示或退出。
- 若 SmartScreen 提示未知发布者，可选择“更多信息”后运行；正式公开发布时建议为程序增加代码签名。

在 Windows 开发机上重新打包：

```powershell
.\build-windows.ps1
```

产物位于 `dist\小小信-Windows-x64.zip`。

## 查看浏览器原型

双击 `index.html` 即可在浏览器打开。也可以在本目录运行：

```bash
python3 -m http.server 5173
```

然后访问 `http://localhost:5173`。

## 当前具备

- macOS 桌面版接入 A 股公开延迟行情与当日分时数据
- 股价采用东方财富主源、腾讯备用源，主源失败时自动切换
- 分时图缓存五分钟，减少公开接口压力和失败概率
- 默认 20 秒自动刷新股价
- 手动刷新
- 桌面版支持输入六位股票代码或中文简称，并从候选结果中选择
- 展开/收起
- 页面内老板键：macOS `Command + Shift + H`，Windows `Ctrl + Shift + H`
- 可替换宠物资源目录
- 点击展开窗口中的小小信可触发跳跃动画和随机回应

## 当前限制

- 当前公开数据源仅适合个人原型验证，正式发布前需要更换或确认数据授权。
- 浏览器原型无法注册系统全局快捷键；macOS 桌面版已实现真正的全局老板键。
- 当前人物图是一张静态初稿，后续将拆分为上涨、下跌、休市等状态资源。
- 当前角色与演唱会互动素材属于原创原型，不代表任何艺人、乐队或品牌的官方产品或授权合作。

## GitHub 发布方式

项目已包含 `.github/workflows/build.yml`：

1. 普通提交可以手动运行工作流，分别生成 macOS 和 Windows 下载包。
2. 推送形如 `v1.0.0` 的标签时，会自动创建 GitHub Release 并附上两个 ZIP。
3. 当前 macOS 构建目标为 Apple Silicon；Intel Mac 通用版本可在后续发布前补充。

## 发布前仍需完成

1. 在真实 Windows 10/11 电脑上验证窗口透明、拖动、托盘和老板键。
2. 确认公开行情接口的数据使用条款，或替换为有授权的生产数据源。
3. 准备应用图标、版本号，以及可选的 Windows/macOS 代码签名。
4. 发布首个版本标签，并验证 GitHub Actions 生成的双平台下载包。

## 参与贡献

欢迎通过 Issue 反馈问题或提交 Pull Request，细节见 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请阅读 [SECURITY.md](SECURITY.md)。

## 开源许可

项目代码按 [MIT License](LICENSE) 发布。
