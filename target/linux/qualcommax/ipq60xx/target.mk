SUBTARGET:=ipq60xx
BOARDNAME:=Qualcomm Atheros IPQ60xx
DEFAULT_PACKAGES += \
	ath11k-firmware-ipq6018 nss-firmware-ipq60xx \
	kmod-nss-ifb kmod-qca-nss-crypto \
	kmod-qca-nss-drv-bridge-mgr kmod-qca-nss-drv-eogremgr kmod-qca-nss-drv-gre \
	kmod-qca-nss-drv-igs kmod-qca-nss-drv-l2tpv2 kmod-qca-nss-drv-lag-mgr \
	kmod-qca-nss-drv-map-t kmod-qca-nss-drv-match kmod-qca-nss-drv-mirror \
	kmod-qca-nss-drv-pppoe kmod-qca-nss-drv-pptp kmod-qca-nss-drv-qdisc \
	kmod-qca-nss-drv-tun6rd kmod-qca-nss-drv-tunipip6 kmod-qca-nss-drv-vlan-mgr kmod-qca-nss-drv-vxlanmgr \
	kmod-qca-mcs kmod-qca-nss-ecm \
	qca-ssdk-shell

define Target/Description
	Build firmware images for Qualcomm Atheros IPQ60xx based boards.
endef
