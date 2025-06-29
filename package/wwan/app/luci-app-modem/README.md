# 中文 | [English](https://github.com/Siriling/5G-Modem-Support/blob/main/EngLish.md)

# luci-app-modem

# 目录

[一、说明](#一说明)

[二、模组支持](#二模组支持)

# 一、说明

- 支持USB和PCIe两种通信方式的通信模组

- 支持配置多个通信模组进行拨号

- 支持IPv6

- 支持高通，紫光展锐，联发科等平台的通信模组

- 支持常见厂商的通信模组（例如：移远，广和通等）

# 二、模组支持

下面列出插件支持的模组

| 厂家名称 | 模组名称                                           | 平台     | 数据传输模式 | 端口模式                     |
| -------- | -------------------------------------------------- | -------- | ------------ | ---------------------------- |
| 华为     | MH5000-31                                          | 华为     | USB          | ECM，NCM                     |
| 移远通信 | RG200U-CN（DONGLE版）                              | 紫光展锐 | USB          | ECM，MBIM，RNDIS，NCM        |
| 移远通信 | RM500U-CN                                          | 紫光展锐 | USB          | ECM，MBIM，RNDIS，NCM        |
| 移远通信 | RM500U-EA                                          | 紫光展锐 | USB          | ECM，MBIM，RNDIS，NCM        |
| 移远通信 | RM500U-CNV                                         | 紫光展锐 | USB          | ECM，MBIM，RNDIS，NCM        |
| 移远通信 | RM500Q-CN                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM500Q-AE                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM500Q-GL                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM502Q-AE                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM502Q-GL                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM505Q-AE                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM520N-CN                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM520N-GL                                          | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 移远通信 | RM500Q-GL                                          | 高通     | PCIE         | RMNET，MBIM                  |
| 移远通信 | RG500Q-EA                                          | 高通     | PCIE         | RMNET，MBIM                  |
| 移远通信 | RM502Q-GL                                          | 高通     | PCIE         | RMNET，MBIM                  |
| 移远通信 | RM520N-GL                                          | 高通     | PCIE         | RMNET，MBIM                  |
| 移远通信 | RG520N-EU                                          | 高通     | PCIE         | RMNET，MBIM                  |
| 广和通   | FM650-CN                                           | 紫光展锐 | USB          | ECM，MBIM，RNDIS，NCM        |
| 广和通   | FM350-GL                                           | 联发科   | USB          | RNDIS                        |
| 广和通   | FM150-AE-01，FM150-AE-11，FM150-AE-21，FM150-NA-01 | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 广和通   | FM350-GL                                           | 联发科   | PCIE         | MBIM                         |
| 广和通   | FM150-AE-00，FM150-AE-10，FM150-AE-20，FM150-NA-00 | 高通     | PCIE         | QMI                          |
| 美格智能 | SRM815                                             | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 美格智能 | SRM825                                             | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
| 美格智能 | SRM825N                                            | 高通     | USB          | RMNET，ECM，MBIM，RNDIS，NCM |
