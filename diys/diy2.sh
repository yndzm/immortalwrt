#!/bin/bash
#=================================================

# 拉取仓库文件夹
function merge_package() {
	# 参数1是分支名,参数2是库地址,参数3是所有文件下载到指定路径。
	# 同一个仓库下载多个文件夹直接在后面跟文件名或路径，空格分开。
	# 示例:
	# merge_package master https://github.com/WYC-2020/openwrt-packages package/openwrt-packages luci-app-eqos luci-app-openclash luci-app-ddnsto ddnsto 
	# merge_package master https://github.com/lisaac/luci-app-dockerman package/lean applications/luci-app-dockerman
	if [[ $# -lt 3 ]]; then
		echo "Syntax error: [$#] [$*]" >&2
		return 1
	fi
	trap 'rm -rf "$tmpdir"' EXIT
	branch="$1" curl="$2" target_dir="$3" && shift 3
	rootdir="$PWD"
	localdir="$target_dir"
	[ -d "$localdir" ] || mkdir -p "$localdir"
	tmpdir="$(mktemp -d)" || exit 1
	git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$curl" "$tmpdir"
	cd "$tmpdir"
	git sparse-checkout init --cone
	git sparse-checkout set "$@"
	# 使用循环逐个移动文件夹
	for folder in "$@"; do
		mv -f "$folder" "$rootdir/$localdir"
	done
	cd "$rootdir"
}

function drop_package(){
	find package/ -follow -name $1 -not -path "package/custom/*" | xargs -rt rm -rf
}

function merge_feed(){
	./scripts/feeds update $1
	./scripts/feeds install -a -p $1
}

echo "开始 DIY2 配置……"
echo "========================="

#chmod +x ${GITHUB_WORKSPACE}/subscript.sh
#source ${GITHUB_WORKSPACE}/subscript.sh

# 修改内核
sed -i 's/PATCHVER:=*.*/PATCHVER:=6.6/g' target/linux/x86/Makefile

# 修改密码
sed -i 's/root:::0:99999:7:::/root:$1$SOP5eWTA$fJV8ty3QohO0chErhlxCm1:18775:0:99999:7:::/g' package/base-files/files/etc/shadow

# 修复上移下移按钮翻译
sed -i 's/<%:Up%>/<%:Move up%>/g' feeds/luci/modules/luci-compat/luasrc/view/cbi/tblsection.htm
sed -i 's/<%:Down%>/<%:Move down%>/g' feeds/luci/modules/luci-compat/luasrc/view/cbi/tblsection.htm

# 修复procps-ng-top导致首页cpu使用率无法获取
sed -i 's#top -n1#\/bin\/busybox top -n1#g' feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci

# unzip
rm -rf feeds/packages/utils/unzip
git clone https://github.com/sbwml/feeds_packages_utils_unzip feeds/packages/utils/unzip

# ppp - 2.5.0
rm -rf package/network/services/ppp
git clone https://github.com/sbwml/package_network_services_ppp package/network/services/ppp

# nghttp3
rm -rf feeds/packages/libs/nghttp3
git clone https://github.com/sbwml/package_libs_nghttp3 feeds/packages/libs/nghttp3

# golang 1.22
rm -rf feeds/packages/lang/golang
git clone https://github.com/sbwml/packages_lang_golang -b 22.x feeds/packages/lang/golang

# 精简 UPnP 菜单名称
sed -i 's#\"title\": \"UPnP IGD \& PCP/NAT-PMP\"#\"title\": \"UPnP\"#g' feeds/luci/applications/luci-app-upnp/root/usr/share/luci/menu.d/luci-app-upnp.json
# 移动 UPnP 到 “网络” 子菜单
sed -i 's/services/network/g' feeds/luci/applications/luci-app-upnp/root/usr/share/luci/menu.d/luci-app-upnp.json

# TTYD 自动登录
sed -i 's|/bin/login|/bin/login -f root|g' feeds/packages/utils/ttyd/files/ttyd.config
# TTYD 更改
sed -i 's/services/system/g' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i '3 a\\t\t"order": 50,' feeds/luci/applications/luci-app-ttyd/root/usr/share/luci/menu.d/luci-app-ttyd.json
sed -i 's/procd_set_param stdout 1/procd_set_param stdout 0/g' feeds/packages/utils/ttyd/files/ttyd.init
sed -i 's/procd_set_param stderr 1/procd_set_param stderr 0/g' feeds/packages/utils/ttyd/files/ttyd.init

## 删除软件
rm -rf feeds/luci/applications/luci-app-adguardhome
rm -rf feeds/packages/net/adguardhome
#rm -rf feeds/luci/themes/luci-theme-bootstrap
rm -rf feeds/luci/applications/luci-app-alist
rm -rf feeds/packages/net/alist
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/{luci-app-v2raya,luci-app-shadowsocks-libev}
rm -rf feeds/packages/net/{v2raya,microsocks,sing-box,shadowsocks-libev,v2ray-core,v2ray-geodata,xray-core}

# 修改include/target.mk
sed -i "s/DEFAULT_PACKAGES.router:=/DEFAULT_PACKAGES.router:=default-settings-chn luci-app-opkg luci-app-firewall /" include/target.mk
sed -i "s/kmod-nft-offload/kmod-nft-offload kmod-nft-tproxy/" include/target.mk

# 修改target/linux/x86/Makefile
sed -i 's/automount/luci-app-homeproxy luci-app-passwall2/g' target/linux/x86/Makefile
#sed -i 's/automount/autocore automount luci-app-diskman luci-app-dockerman luci-app-passwall2 luci-app-ttyd luci-app-udpxy/g' target/linux/x86/Makefile

# 修正部分从第三方仓库拉取的软件 Makefile 路径问题
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/..\/..\/lang\/golang\/golang-package.mk/$(TOPDIR)\/feeds\/packages\/lang\/golang\/golang-package.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {}

# 自定义默认配置
sed -i '/exit 0$/d' package/emortal/default-settings/files/99-default-settings
cat ${GITHUB_WORKSPACE}/default-settings >> package/emortal/default-settings/files/99-default-settings

# 拷贝自定义文件
#if [ -n "$(ls -A "${GITHUB_WORKSPACE}/immortalwrt/diy" 2>/dev/null)" ]; then
	#cp -Rf ${GITHUB_WORKSPACE}/immortalwrt/diy/* .
#fi


echo "========================="
echo " DIY2 配置完成……"
