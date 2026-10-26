#!/bin/sh

# baylavdev bootstrap — Arch/Artix auto-rice
# Luke Smith'in LARBS'ından türetildi, kişiselleştirildi.
# License: GNU GPLv3

### DEĞİŞKENLER ###
dotfilesrepo="https://github.com/baylavdev/dotfiles.git"
progsfile="https://raw.githubusercontent.com/baylavdev/bootstrap/master/progs.csv"
aurhelper="yay"
repobranch="master"
export TERM=ansi

# Kendi RSS/YouTube feed'lerin (newsboat). Luke'unkiler çıkarıldı.
rssurls="https://baylav.org/rss.xml
# https://www.youtube.com/feeds/videos.xml?channel_id=XXXX \"~Kanal\""

### YARDIMCI ###
is_wsl() { grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; }
installpkg() { pacman --noconfirm --needed -S "$1" >/dev/null 2>&1; }
error() { printf "%s\n" "$1" >&2; exit 1; }

welcomemsg() {
	whiptail --title "baylavdev bootstrap" \
		--msgbox "baylavdev otomatik kurulum scriptine hoş geldin.\\n\\nTam donanımlı bir Arch/Artix masaüstü kurulacak." 10 60
	whiptail --title "Not" --yes-button "Hazır" --no-button "Geri..." \
		--yesno "pacman güncel, Arch keyring'leri taze olsun; değilse bazı paketler kurulamaz." 8 70
}

getuserandpass() {
	name=$(whiptail --inputbox "Kullanıcı adı:" 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel --inputbox "Geçersiz. Harfle başlasın, küçük harf/-/_ olsun." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(whiptail --nocancel --passwordbox "Parola:" 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(whiptail --nocancel --passwordbox "Parola (tekrar):" 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(whiptail --nocancel --passwordbox "Eşleşmedi. Parola:" 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(whiptail --nocancel --passwordbox "Parola (tekrar):" 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

usercheck() {
	! { id -u "$name" >/dev/null 2>&1; } ||
		whiptail --title "UYARI" --yes-button "DEVAM" --no-button "Dur..." \
			--yesno "\`$name\` zaten var. Çakışan ayar/dotfiles ÜZERİNE YAZILIR (dosyaların korunur). Parola da değişir." 14 70
}

preinstallmsg() {
	whiptail --title "Başlıyoruz" --yes-button "Hadi!" --no-button "Vazgeç" \
		--yesno "Geri kalanı otomatik. Biraz sürer, bitince hazır sistem seni bekliyor." 13 60 || { clear; exit 1; }
}

adduserandpass() {
	whiptail --infobox "Kullanıcı \"$name\" ekleniyor..." 7 50
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
		usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	export repodir="/home/$name/.local/src"
	mkdir -p "$repodir"
	chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

refreshkeys() {
	case "$(readlink -f /sbin/init)" in
	*systemd*)
		whiptail --infobox "Arch keyring yenileniyor..." 7 40
		pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1 ;;
	*)
		whiptail --infobox "Artix: Arch depoları etkinleştiriliyor..." 7 40
		pacman --noconfirm --needed -S artix-keyring artix-archlinux-support >/dev/null 2>&1
		grep -q "^\[extra\]" /etc/pacman.conf ||
			echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		pacman -Sy --noconfirm >/dev/null 2>&1
		pacman-key --populate archlinux >/dev/null 2>&1 ;;
	esac
}

manualinstall() {
	pacman -Qq "$1" && return 0
	whiptail --infobox "\"$1\" elle kuruluyor." 7 50
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{ cd "$repodir/$1" || return 1; sudo -u "$name" git pull --force origin master; }
	cd "$repodir/$1" || exit 1
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	whiptail --title "baylavdev" --infobox "\`$1\` ($n/$total). $2" 9 70
	installpkg "$1"
}

gitmakeinstall() {
	progname="${1##*/}"; progname="${progname%.git}"
	dir="$repodir/$progname"
	whiptail --title "baylavdev" --infobox "\`$progname\` ($n/$total) git+make. $2" 8 70
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{ cd "$dir" || return 1; sudo -u "$name" git pull --force origin master; }
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

aurinstall() {
	whiptail --title "baylavdev" --infobox "\`$1\` ($n/$total) AUR. $2" 9 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	whiptail --title "baylavdev" --infobox "pip: \`$1\` ($n/$total). $2" 9 70
	[ -x "$(command -v pip)" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

urlinstall() {
	# "U" tag: doğrudan URL'den paket (ör. Synergy .pkg.tar.zst)
	whiptail --title "baylavdev" --infobox "\`$(basename "$1")\` ($n/$total) URL'den. $2" 9 70
	pacman -U --noconfirm --needed "$1" >/dev/null 2>&1
}

installationloop() {
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
	total=$(wc -l </tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n + 1))
		echo "$comment" | grep -q "^\".*\"$" &&
			comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
		"A") aurinstall "$program" "$comment" ;;
		"G") gitmakeinstall "$program" "$comment" ;;
		"P") pipinstall "$program" "$comment" ;;
		"U") urlinstall "$program" "$comment" ;;
		*) maininstall "$program" "$comment" ;;
		esac
	done </tmp/progs.csv
}

putgitrepo() {
	whiptail --infobox "Config dosyaları indiriliyor..." 7 60
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q --recursive -b "$branch" --recurse-submodules "$1" "$dir"
	sudo -u "$name" cp -rfT "$dir" "$2"
}

vimplugininstall() {
	whiptail --infobox "neovim eklentileri..." 7 60
	mkdir -p "/home/$name/.config/nvim/autoload"
	curl -Ls "https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim" > "/home/$name/.config/nvim/autoload/plug.vim"
	chown -R "$name:wheel" "/home/$name/.config/nvim"
	sudo -u "$name" nvim -c "PlugInstall|q|q"
}

finalize() {
	whiptail --title "Bitti!" \
		--msgbox "Kurulum tamam. Çıkış yapıp yeni kullanıcıyla gir, \"startx\" ile masaüstü açılır (tty1'de otomatik başlar).\\n\\n- baylavdev" 13 80
}

### AKIŞ ###
pacman --noconfirm --needed -Sy libnewt ||
	error "Root musun? Arch tabanlı bir sistemde ve internete bağlı mısın?"
welcomemsg || error "Kullanıcı çıktı."
getuserandpass || error "Kullanıcı çıktı."
usercheck || error "Kullanıcı çıktı."
preinstallmsg || error "Kullanıcı çıktı."
refreshkeys || error "Keyring yenilenemedi."

for x in curl ca-certificates base-devel git ntp zsh dash; do
	whiptail --title "baylavdev" --infobox "\`$x\` kuruluyor (gerekli araç)." 8 70
	installpkg "$x"
done

# Saat senkronu — WSL'de atlanır (RTC yok)
if ! is_wsl; then
	whiptail --title "baylavdev" --infobox "Saat senkronize ediliyor..." 8 70
	ntpd -q -g >/dev/null 2>&1
fi

adduserandpass || error "Kullanıcı/parola hatası."
[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers

trap 'rm -f /etc/sudoers.d/baylav-temp' HUP INT QUIT TERM PWR EXIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL
Defaults:%wheel,root runcwd=*" >/etc/sudoers.d/baylav-temp

grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

manualinstall $aurhelper || error "AUR helper kurulamadı."
$aurhelper -Y --save --devel

installationloop

putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -rf "/home/$name/.git/" "/home/$name/README.md" "/home/$name/LICENSE" "/home/$name/FUNDING.yml"

[ -s "/home/$name/.config/newsboat/urls" ] ||
	echo "$rssurls" | sudo -u "$name" tee "/home/$name/.config/newsboat/urls" >/dev/null

[ ! -f "/home/$name/.config/nvim/autoload/plug.vim" ] && vimplugininstall

chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/" "/home/$name/.config/abook/" "/home/$name/.config/mpd/playlists/"
ln -sfT /bin/dash /bin/sh >/dev/null 2>&1

# ---- GUI / DONANIM: WSL'de tamamen atlanır ----
if ! is_wsl; then
	rmmod pcspkr 2>/dev/null
	echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

	dbus-uuidgen >/var/lib/dbus/machine-id 2>/dev/null
	[ "$(readlink -f /sbin/init)" != "/usr/lib/systemd/systemd" ] && echo "export \$(dbus-launch)" >/etc/profile.d/dbus.sh

	[ ! -f /etc/X11/xorg.conf.d/40-libinput.conf ] && printf 'Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
	Option "Tapping" "on"
EndSection' >/etc/X11/xorg.conf.d/40-libinput.conf

	# Librewolf + Arkenfox — istemezsen bu bloğu komple sil
	whiptail --infobox "Tarayıcı gizlilik ayarları..." 7 60
	browserdir="/home/$name/.librewolf"; profilesini="$browserdir/profiles.ini"
	sudo -u "$name" librewolf --headless >/dev/null 2>&1 &
	sleep 1
	profile="$(sed -n "/Default=.*.default-default/ s/.*=//p" "$profilesini")"
	pdir="$browserdir/$profile"
	if [ -d "$pdir" ]; then
		arkenfox="$pdir/arkenfox.js"; overrides="$pdir/user-overrides.js"; userjs="$pdir/user.js"
		ln -fs "/home/$name/.config/firefox/baylav.js" "$overrides"
		[ ! -f "$arkenfox" ] && curl -sL "https://raw.githubusercontent.com/arkenfox/user.js/master/user.js" > "$arkenfox"
		cat "$arkenfox" "$overrides" > "$userjs"
		chown "$name:wheel" "$arkenfox" "$userjs"
	fi
	pkill -u "$name" librewolf
fi
# ------------------------------------------------

echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-baylav-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu" >/etc/sudoers.d/01-baylav-cmds
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d/02-baylav-visudo-editor
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

rm -f /etc/sudoers.d/baylav-temp
finalize
