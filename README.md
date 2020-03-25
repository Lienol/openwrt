本源码生成的固件禁止使用在任何非法、商业用途！

编译命令如下（引用大雕的README）:

1. 首先装好 Ubuntu 64bit，推荐  Ubuntu  18 LTS x64

2. 命令行输入 sudo apt-get update ，然后输入
sudo apt-get -y install build-essential asciidoc binutils bzip2 gawk gettext git libncurses5-dev libz-dev patch python3.5 unzip zlib1g-dev lib32gcc1 libc6-dev-i386 subversion flex uglifyjs git-core gcc-multilib p7zip p7zip-full msmtp libssl-dev texinfo libglib2.0-dev xmlto qemu-utils upx libelf-dev autoconf automake libtool autopoint device-tree-compiler g++-multilib

3. git clone -b dev-lean-lede https://github.com/Lienol/openwrt lean-lede 命令下载好源代码，然后 cd lean-lede 进入目录

4. ./scripts/feeds clean

   ./scripts/feeds update -a
   
   ./scripts/feeds install -a
   
   make menuconfig 

5. 最后选好你要的路由，输入 make -j1 V=s （-j1 后面是线程数。第一次编译推荐用单线程，国内请尽量全局科学上网）即可开始编译你要的固件了。

上游：https://github.com/coolsnowwolf/lede
