# Rainyun 雨云自动签到（Docker 镜像）

把雨云每日签到跑在容器里：镜像内置 Google Chrome 与同版本 ChromeDriver，自动识别登录验证码（ICR），跑一次即退出，定时交给外部 cron / 计划任务。

支持 `linux/amd64` 与 `linux/arm64`。

## 鸣谢

- 业务逻辑来自原项目 **[chizw/Rainyun-Qiandao](https://github.com/chizw/Rainyun-Qiandao)**：`rainyun.py`、`notify.py`、`ICR.py`、`stealth.min.js` 均为原项目代码，本仓库未改动。
- 验证码识别（ICR）与浏览器指纹隐身脚本的原始实现同样归功于原项目及其上游开源作者。
- 感谢雨云提供签到活动，以及所有为这类脚本贡献过思路与代码的人。

本仓库只做 Docker 化封装：多架构镜像、Chrome/ChromeDriver 版本对齐、Cookie 持久化、时区与体积优化。

## 镜像

```bash
docker pull ghcr.io/cmsz001/rainyun-qiandao-docker:latest
```

- 基础镜像 `python:3.9-slim`，多阶段构建，运行期不含编译器与下载工具
- 浏览器为 [Chrome for Testing](https://googlechromelabs.github.io/chrome-for-testing/) Stable 通道的完整版 Chrome，ChromeDriver 同版本号（构建期断言主版本一致）
- 时区固定 `Asia/Shanghai`（`TZ` + `/etc/localtime`），容器日志时间即北京时间
- 容器内以 root 运行并带 `--no-sandbox`，这是让 Chrome 在容器里稳定启动的最简做法

> 首次推送后，需要到 GitHub → Packages 把该包设为 **Public**，否则 `docker pull` 需要先 `docker login ghcr.io`。

## 快速开始

```bash
docker run --rm \
  -e RAINYUN_USER='user1' \
  -e RAINYUN_PASS='pass1' \
  -v rainyun-cookies:/app/temp/cookies \
  ghcr.io/cmsz001/rainyun-qiandao-docker:latest
```

多账户用换行分隔，账号与密码行数必须对应：

```bash
docker run --rm \
  -e RAINYUN_USER=$'user1\nuser2' \
  -e RAINYUN_PASS=$'pass1\npass2' \
  -v rainyun-cookies:/app/temp/cookies \
  ghcr.io/cmsz001/rainyun-qiandao-docker:latest
```

变量多时建议 `--env-file .env`（`.env` 别提交进仓库）。

## 数据持久化

Cookie 存在容器内 `temp/cookies/{account_hash}.json`。挂上卷之后第二次运行可跳过验证码：

```bash
-v rainyun-cookies:/app/temp/cookies
```

用命名卷而不是绑定宿主机目录，可以避免容器内 root 在宿主机上留下属主为 root 的目录。

## 定时执行

容器跑完一次就退出，定时由外部负责：

```bash
# 每天 04:00
0 4 * * * docker run --rm -e RAINYUN_USER=... -e RAINYUN_PASS=... -v rainyun-cookies:/app/temp/cookies ghcr.io/cmsz001/rainyun-qiandao-docker:latest
```

Windows 用「任务计划程序」或 `schtasks` 调同一条 `docker run` 即可。

## 环境变量

必需：

| 变量 | 说明 |
| --- | --- |
| `RAINYUN_USER` | 雨云用户名，多账户换行分隔 |
| `RAINYUN_PASS` | 雨云密码，多账户换行分隔，与用户名逐行对应 |

常用：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `MAX_WORKERS` | `2`（镜像内设定） | 并发线程数 |
| `CHECKIN_MAX_RETRIES` | 代码内默认 | 单个账号签到重试次数（注意名字是 `CHECKIN_MAX_RETRIES`） |
| `MAX_DELAY` | 代码内默认 | 账号之间的随机延迟上限（秒） |
| `TIMEOUT` | `15000` | 页面加载超时（毫秒） |
| `DEBUG` | `false` | 输出详细日志 |
| `NOTIFY_ONLY_FAILURE` | `false` | 只在有账号失败时推送 |
| `SKIP_PUSH_TITLE` | 空 | 推送标题跳过替换，一般不用设 |

推送渠道沿用原项目 `notify.py` 的变量名，例如 `PUSH_KEY`（Server 酱）、`TG_BOT_TOKEN` + `TG_USER_ID`（Telegram）、`QYWX_KEY`（企业微信机器人）、`DD_BOT_TOKEN` + `DD_BOT_SECRET`（钉钉）、`BARK_*`、`PUSH_PLUS_TOKEN`、`SMTP_*` 等，完整清单见 `notify.py` 顶部的 `push_config`。

镜像 `ENV` 里另有一些历史变量（`HEADLESS`、`MAX_RETRIES`、`CHROMEDRIVER_PATH`），业务代码并不读取，设了也没效果；无头模式由 `LINUX_MODE=true`（或存在 `/.dockerenv`）自动开启。

## 自行构建

单架构：

```bash
docker build -t rainyun-checkin:slim .
docker run --rm rainyun-checkin:slim google-chrome --version
```

多架构并推送：

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/<你的用户名>/rainyun-qiandao-docker:latest --push .
```

构建分两阶段：`builder` 只负责下载 CfT 的 Chrome 与 ChromeDriver、装 Python 依赖；`final` 只保留浏览器、驱动、依赖与四个业务文件，并剔除 Chrome 自带的多余语言包。

## 免责声明

仅供学习与自动化实践。脚本可能违反雨云用户协议，账号风险自负；请遵守目标站点的使用条款，不要高频请求。
