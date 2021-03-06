
## OpenAppFilter功能简介

OpenAppFilter模块基于数据流深度识别技术，实现对单个app进行管控的功能，并支持上网记录统计

### 过滤效果演示视频
https://www.bilibili.com/video/BV11z4y1z7tQ/  

### 主要使用场景
	- 家长对小孩上网行为进行管控，限制小孩玩游戏等
	- 限制员工使用某些app， 如视频、招聘、购物、游戏、常用网站等
	- 记录终端的上网记录，实时了解当前app使用情况，比如xxx正在访问抖音
	
### 插件截图
#### 1
![main1](https://github.com/destan19/images/blob/master/oaf/main1.png)


#### 2
![main2](https://github.com/destan19/images/blob/master/oaf/main2.png)

### 支持app列表(只列主流)
 - 游戏
   王者荣耀 英雄联盟 欢乐斗地主 梦幻西游 明日之后 ...
 - 音乐
 - 购物
   淘宝 京东 唯品会 拼多多 苏宁易购
 - 聊天
	QQ 微信 钉钉 
 - 招聘
 - 视频
   抖音小视频 斗鱼直播 腾讯视频 爱奇艺 火山小视频 YY 微视 虎牙直播 快手 小红书 ...

## 编译说明
1. 下载OpenWrt源码，并完成编译(OpenWrt公众号有相关教程）
> git clone https://github.com/coolsnowwolf/lede.git  
> 或 https://github.com/openwrt/openwrt.git  
2. 下载应用过滤源码放到OpenWrt的package 目录
> cd package  
git clone https://github.com/destan19/OpenAppFilter.git  
cd -
3. make menuconfig, 在luci app中选上luci oaf app模块并保存 
4. make V=s 编译出带应用过滤功能的OpenWrt固件 

## 使用说明
应用过滤和加速模块（Turbo ACC)有冲突，需要关闭Turboo ACC后使用



## 存在的问题
- 该模块只工作在路由模式， 旁路模式、桥模式不生效  
- 存在小概率误判的情况，特别是同一个公司的app，比如淘宝、支付宝等，如果需要过滤，建议相似的app全部勾选  
- 暂不兼容OpenWrt主干的luci，如果报错，请使用老一点的版本（OpenWrt18.06或lean 的lede源码）  

## 技术交流

### 微信公众号
OpenWrt (获取应用过滤最新固件和OpenWrt教程)
![weixin](https://github.com/destan19/images/blob/master/oaf/qr.png)
### 技术交流QQ群 
- 群一:943396288(已满)  
- 群二:1046680252（已满）
- 群三:868508199  
点击链接加入群聊【OpenWrt技术交流】：https://jq.qq.com/?_wv=1027&k=vbmB1SUX

