# 🚀 wsl2host-port-bridge

WSL2 端口转发管理脚本，配合 `wsl2host` 项目，一键管理端口转发，简化 Windows 与 WSL2 之间的网络互通。

当wsl需要远程访问时会因为wsl2的ip变化而连接不上，使用 `wsl2host` 将ip固定，再使用本项目将端口转发到windows上，即可实现远程访问wsl。


## 🤝 前提：安装wsl2host

1. 从wsl2host项目下载并解压[release](https://github.com/shayne/go-wsl2-host/releases/latest)[![](https://img.shields.io/badge/wsl2host-release-blue.svg)]({https://github.com/shayne/go-wsl2-host/releases/latest})


2. 使用管理员模式终端命令提示符运行：
    ```bash
    .\wsl2host.exe install
    ```
    输入windows系统当前的用户名和账户密码，写错了后面可以改
    ```bash
    Windows Username: 当前登录的用户名
    Windows Password: 账户密码（注意不是PIN）
    ```
3. 在本地安全策略```secpol.msc```中，找到本地策略-用户分配权限 ,找到```作为服务登录```把当前电脑登录用户名加入进去
![效果展示](/readme/本地安全策略.png)

#### 在服务中看到wsl2host正在运行就成功了
![效果展示](/readme/本地安全策略.png)
[!TIP]
你可以在这里属性-登录选项卡里更改你登录的账户密码，但要记得更改后确保此用户在```作为服务登录```里



## 📦 安装 (Installation)


在 WSL2 终端中运行以下命令：
```bash
curl -fsSL https://raw.githubusercontent.com/sjtt2/wsl2host-port-bridge/main/install.sh | sudo bash
```

## 🗑️ 卸载 (Uninstallation)

```bash
curl -fsSL https://raw.githubusercontent.com/sjtt2/wsl2host-port-bridge/main/uninstall.sh | sudo bash
```


## 🚀 使用方法 (Usage)

| 命令 | 说明 | 示例 |
|------|------|------|
| `port add <端口号>` | 添加端口转发（立即生效） | `port add 22` |
| `port open <端口号>` | 同 `add`，添加端口转发 | `port open 8080` |
| `port delete <端口号>` | 删除端口转发（立即失效） | `port delete 22` |
| `port ban <端口号>` | 同 `delete`，删除端口转发 | `port ban 8080` |
| `port list` | 查看所有已配置端口 | `port list` |
| `port ls` | 同 `list`，查看已配置端口 | `port ls` |
| `port check` | 同 `list`，查看已配置端口 | `port check` |
| `port help` | 显示帮助信息 | `port help` |



## 📄 许可证 (License)

本项目采用 [MIT 许可证](LICENSE) 开源，允许自由使用、修改和分发。


## 🔗 相关项目

- [wsl2host](https://github.com/sjtt2/wsl2host)