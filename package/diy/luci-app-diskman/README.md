# Luci-app-diskman

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/lisaac/luci-app-diskman?style=flat-square)](https://github.com/lisaac/luci-app-diskman/releases)
[![GitHub stars](https://img.shields.io/github/stars/lisaac/luci-app-diskman?style=flat-square)](https://github.com/lisaac/luci-app-diskman/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/lisaac/luci-app-diskman?style=flat-square)](https://github.com/lisaac/luci-app-diskman/network/members)
[![License](https://img.shields.io/github/license/lisaac/luci-app-diskman?style=flat-square)](https://github.com/lisaac/luci-app-diskman/blob/master/LICENSE)
[![Telegram Group](https://img.shields.io/badge/telegam-group-_?style=flat-square)](https://t.me/joinchat/G5mqjhrlU9S8TMkXeBmj0w)
- A Simple Disk Manager for LuCI, support disk partition and format, support raid / btrfs-raid / btrfs-snapshot
- 一个简单的磁盘管理 LuCI 插件，支持磁盘分区、格式化，支持 RAID / btrfs-raid / btrfs-快照管理
- [Download / 下载 ipk](https://github.com/lisaac/luci-app-diskman/releases)

## Depends / 依赖
- [parted](https://github.com/lisaac/luci-app-diskman/blob/master/Parted.Makefile)
- blkid
- smartmontools
- e2fsprogs
- btrfs-progs (Optional)
- lsblk (Optional)
- mdadm (Optional)
    - kmod-md-raid456 (Optional)
    - kmod-md-linear (Optional)

## Compile / 编译
``` bash
mkdir -p package/luci-app-diskman && \
wget https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/Makefile -O package/luci-app-diskman/Makefile
mkdir -p package/parted && \
wget https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/Parted.Makefile -O package/parted/Makefile

#compile package only
make package/luci-app-diskman/compile V=99

#compile
make menuconfig
#choose LuCI ---> 3. Applications  ---> <*> luci-app-diskman..... Disk Manager interface for LuCI ----> save
make V=99

```

## Screenshot / 截图
- Disk Info
![](https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/doc/disk_info.png)
- Partitions Info
![](https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/doc/partitions_info.png)

## Thanks / 谢致
- [luci-app-diskmanager](http://eko.one.pl/forum/viewtopic.php?id=18669)
- [luci-app-smartinfo](https://github.com/animefansxj/luci-app-smartinfo)
- Chinese translation by [锤子](https://www.right.com.cn/forum/space-uid-311750.html)
