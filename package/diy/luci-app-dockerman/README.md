# Luci-app-dockerman

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/lisaac/luci-app-dockerman?style=flat-square)](https://github.com/lisaac/luci-app-dockerman/releases)
[![GitHub stars](https://img.shields.io/github/stars/lisaac/luci-app-dockerman?style=flat-square)](https://github.com/lisaac/luci-app-dockerman/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/lisaac/luci-app-dockerman?style=flat-square)](https://github.com/lisaac/luci-app-dockerman/network/members)
[![License](https://img.shields.io/github/license/lisaac/luci-app-dockerman?style=flat-square)](https://github.com/lisaac/luci-app-dockerman/blob/master/LICENSE)
[![Telegram Group](https://img.shields.io/badge/telegam-group-_?style=flat-square)](https://t.me/joinchat/G5mqjhrlU9S8TMkXeBmj0w)
<!-- ![GitHub All Releases](https://img.shields.io/github/downloads/lisaac/luci-app-dockerman/total?style=flat-square) -->

## Docker Manager for LuCI / 适用于 LuCI 的 Docker 管理插件
- 一个用于管理 Docker 容器、镜像、网络、存储卷的 Openwrt 插件
- 同时也适用于 [Openwrt-in-docker](https://github.com/lisaac/openwrt-in-docker) 或 [LuCI-in-docker](https://github.com/lisaac/luci-in-docker)
- [Download / 下载 ipk](https://github.com/lisaac/luci-app-dockerman/releases)

## Depends / 依赖
- [luci-lib-docker](https://github.com/lisaac/luci-lib-docker)
- docker-ce (optional, since you can use it as a docker client)
- luci-lib-jsonc
- ttyd (optional, use for container console)

## Compile / 编译
```bash
mkdir -p package/luci-lib-docker && \
wget https://raw.githubusercontent.com/lisaac/luci-lib-docker/master/Makefile -O package/luci-lib-docker/Makefile
mkdir -p package/luci-app-dockerman && \
wget https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/Makefile -O package/luci-app-dockerman/Makefile

#compile package only
make package/luci-lib-jsonc/compile V=99
make package/luci-lib-docker/compile v=99
make package/luci-app-dockerman/compile v=99

#compile
make menuconfig
#choose Utilities  ---> <*> docker-ce....................................... Docker Community Edition
#choose Kernel features for Docker which you want
#choose LuCI ---> 3. Applications  ---> <*> luci-app-dockerman..... Docker Manager interface for LuCI ----> save
make V=99
```

## Screenshot / 截图
- Containers
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/containers.png)
- Container Info
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/container_info.png)
- Container Edit
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/container_edit.png)
- Container Stats
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/container_stats.png)
- Container Logs
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/container_logs.png)
- New Container
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/new_container.png)
- Images
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/images.png)
- Networks
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/networks.png)
- New Network
![](https://raw.githubusercontent.com/lisaac/luci-app-dockerman/master/doc/new_network.png)

## Thanks / 谢致
- Chinese translation by [401626436](https://www.right.com.cn/forum/space-uid-382335.html)