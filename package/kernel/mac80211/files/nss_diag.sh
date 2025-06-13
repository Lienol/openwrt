#!/bin/sh
# shellcheck disable=3037,3060,2034,1091,2166

# check if stdout is a terminal, then set colors.
if [ -t 1 ]; then
  red="\033[31m"
  green="\033[32m"
  yellow="\033[33m"
  blue="\033[34m"
  magenta="\033[35m"
  cyan="\033[36m"
  white="\033[37m"
  reset="\033[m"
  bold="\033[1m"
fi

# Retrieve OpenWRT version
[ -r /etc/openwrt_version ] && openwrt_rev=$(cat /etc/openwrt_version)

# Retrieve device model
model=$(jsonfilter -e ''@.model.name'' < /etc/board.json | sed -e "s/,/_/g")

# NSS firmware version
nss_fw="/lib/firmware/qca*.bin"
# shellcheck disable=2086
[ "$(ls $nss_fw 2> /dev/null)" ] && nss_version=$(grep -h -m 1 -a -o 'Version:.[^[:cntrl:]]*' $nss_fw | head -1 | cut -d ' ' -f 2)

# ATH11K firmware version
ath11k_fw=$(grep -hm1 -a -o 'WLAN.[^[:cntrl:]]*SILICONZ-1' /lib/firmware/*/q6* | head -1)

# MAC80211 (backports) version
mac80211_version=$(awk '/version/{print $NF;exit}' /lib/modules/*/compat.ko)

# OpenWRT IPQ release details
[ -r /etc/ipq_release ] && . /etc/ipq_release
ipq_branch=${IPQ_BRANCH:-"N/A"}
ipq_commit=${IPQ_COMMIT:-"N/A"}
ipq_date=${IPQ_DATE:-"N/A"}

# Defaults for empty variables
openwrt_rev=${openwrt_rev:-"N/A"}
model=${model:-"N/A"}
nss_version=${nss_version:-"N/A"}
ath11k_fw=${ath11k_fw:-"N/A"}
mac80211_version=${mac80211_version:-"N/A"}

# Display the information
echo -e "${bold}${red}     MODEL${reset}: ${blue}${bold}${model}${reset}"
echo -e "${bold}${red}   OPENWRT${reset}: ${white}${openwrt_rev}${reset}"
echo -e "${bold}${red}IPQ BRANCH${reset}: ${cyan}${ipq_branch}${reset}"
echo -e "${bold}${red}IPQ COMMIT${reset}: ${cyan}${ipq_commit}${reset}"
echo -e "${bold}${red}  IPQ DATE${reset}: ${cyan}${ipq_date}${reset}"
echo -e "${bold}${red}    NSS FW${reset}: ${magenta}${nss_version}${reset}"
echo -e "${bold}${red}  MAC80211${reset}: ${yellow}${mac80211_version}${reset}"
echo -e "${bold}${red} ATH11K FW${reset}: ${green}${ath11k_fw}${reset}"

# Display GRO Fragmentation status using BusyBox
echo -ne "${bold}${red} INTERFACE${reset}: ${white}"
n=0
for iface in /sys/class/net/br-lan/device /sys/class/net/*/device; do
  iface=${iface%/*}
  iface=${iface##*/}
  ethtool -k "$iface" | awk -v n=$n -v i="$iface" -v rst="${reset}" -v red="${red}" -v green="${green}" '
    BEGIN { settings=""; if(n>0) spacing="            " }
    /tx-checksumming|rx-gro-list/ {
      color=green
      if($2=="off") color=red
      settings = settings $1 " " sprintf("%s%-3s%s", color,$2,rst) " ";
    }
  END { printf "%s%-11s%s\n", spacing, i, settings; }'
  n=$((n + 1))
done

echo -e "${reset}"
echo -ne "${bold}${red}  NSS PKGS${reset}: ${white}"

if cmd=$(command -v apk) > /dev/null; then
  flags="list -I"
else
  cmd=$(command -v opkg)
  flags="list-installed"
fi

if [ -z "$cmd" ]; then
  echo -e "${red}No package manager found${reset}"
  exit 1
fi

$cmd $flags | awk -v count=0 '
  /kmod-qca|^nss/ {
  if(count>0) tab="            "
  print tab $0
  count++
}'
echo -ne "${reset}"
