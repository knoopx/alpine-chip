.PHONY: target flash flash-ubi reboot-flash $(ALPINE_CHROOT)

ARCH 					:= armhf
ALPINE_CHROOT := /alpine
ALPINE_BRANCH := edge
ALPINE_MIRROR := http://dl-cdn.alpinelinux.org/alpine

KERNEL_VERSION 			:= 4.4.13-ntc-mlc
KERNEL_REV_ARCH 		:= 4.4.13-58
MP_DRIVER_REV_ARCH 	:= 4.3.16-13854.20150410-BTCOEX20150119-5844-ntc-2
CHIP_APT_REPO 			:= http://chip.jfpossibilities.com/chip/debian/repo

SYSTEM_USER 						:= chip
SYSTEM_HOSTNAME 				:= chip
SYSTEM_KEYBOARD_LAYOUT 	:= es
SYSTEM_KEYBOARD_VARIANT := es
SYSTEM_TIMEZONE 				:= Europe/Madrid

NAND_MAXLEB_COUNT 		:= 4096
NAND_PAGE_SIZE 				:= 16384
NAND_SUBPAGE_SIZE 		:= 16384
NAND_ERASE_BLOCK_SIZE := 4194304
NAND_OOB_SIZE 				:= 1664

SPL_MEM_ADDR 					:= 0x43000000
UBOOT_SCRIPT_MEM_ADDR := 0x43100000
UBOOT_MEM_ADDR 				:= 0x4a000000

BOOT_CMD = 'if test -n \$${fel_booted} && test -n \$${scriptaddr}; then echo '(FEL boot)'; source \$${scriptaddr}; fi; mtdparts; ubi part UBI; ubifsmount ubi0:rootfs; ubifsload \$$fdt_addr_r /boot/sun5i-r8-chip.dtb; ubifsload \$$kernel_addr_r /boot/zImage; bootz \$$kernel_addr_r - \$$fdt_addr_r'
BOOT_ARGS = 'root=ubi0:rootfs rootfstype=ubifs rw earlyprintk ubi.mtd=4'

FASTBOOT_DEVICE_ID := 0x1f3a

NAND_ERASE_BLOCK_SIZE_X := $(shell printf %x $(NAND_ERASE_BLOCK_SIZE))
NAND_PAGE_SIZE_X := $(shell printf %x $(NAND_PAGE_SIZE))
NAND_OOB_SIZE_X := $(shell printf %x $(NAND_OOB_SIZE))

target: dist/rootfs.ubi.sparse

docker:
	docker build runner -t runner
	docker run --privileged --rm -v /dev:/dev:ro -v $(PWD):/runner -w /runner runner make

reboot-flash: dist/flash.scr
	sunxi-fel -v -p \
		spl boot/sunxi-spl.bin \
		write $(SPL_MEM_ADDR) boot/sunxi-spl-with-ecc.bin \
		write $(UBOOT_MEM_ADDR) boot/u-boot-dtb.bin \
		write $(UBOOT_SCRIPT_MEM_ADDR) dist/flash.scr \
		exe $(UBOOT_MEM_ADDR)

flash: reboot-flash flash-ubi
	fastboot -i $(FASTBOOT_DEVICE_ID) continue -u

flash-ubi: dist/rootfs.ubi.sparse
	fastboot -i $(FASTBOOT_DEVICE_ID) erase UBI
	fastboot -i $(FASTBOOT_DEVICE_ID) flash UBI dist/rootfs.ubi.sparse

dist/flash.scr:
	cat <<-UBOOT_SCRIPT > dist/flash.cmd
		nand erase.chip
		nand write.raw.noverify $(SPL_MEM_ADDR) 0x0 0x400000 # spl
		nand write.raw.noverify $(SPL_MEM_ADDR) 0x400000 0x400000 # spl-backup
		nand write $(UBOOT_MEM_ADDR) 0x800000 0x400000 # uboot

		env default -a
		setenv bootargs $(BOOT_ARGS)
		setenv bootcmd $(BOOT_CMD)
		setenv fel_booted 0

		setenv stdin serial
		setenv stdout serial
		setenv stderr serial
		saveenv
		fastboot 0
		mw \$${scriptaddr} 0x0
		boot
	UBOOT_SCRIPT

	mkimage -A arm -T script -C none -n "flash" -d dist/flash.cmd $@

.ONESHELL:
dist/ubinize.cfg:
	cat <<-UBINIZE > $@
		[rootfs]
		mode=ubi
		vol_id=0
		vol_type=dynamic
		vol_name=rootfs
		vol_alignment=1
		vol_flags=autoresize
		image=dist/rootfs.ubifs
	UBINIZE

dist/rootfs.ubi.sparse: dist/rootfs.ubi
	img2simg 	$< $@ $(NAND_ERASE_BLOCK_SIZE)

dist/rootfs.ubifs: $(ALPINE_CHROOT)
	mkfs.ubifs -d $(ALPINE_CHROOT) -m 16384 -e 2064384 -c 4096 -o $@

dist/rootfs.ubi: dist/ubinize.cfg dist/rootfs.ubifs
	ubinize -o $@ -p $(NAND_ERASE_BLOCK_SIZE) -m $(NAND_PAGE_SIZE) -s $(NAND_SUBPAGE_SIZE) -M dist3 dist/ubinize.cfg

.ONESHELL:
$(ALPINE_CHROOT): vendor/linux-image-$(KERNEL_VERSION)_$(KERNEL_REV_ARCH)_$(ARCH).deb vendor/rtl8723bs-mp-driver-modules-$(KERNEL_VERSION)_$(MP_DRIVER_REV_ARCH)+$(KERNEL_REV_ARCH)_all.deb
	scripts/alpine-chroot-install -d $(ALPINE_CHROOT) -a $(ARCH) -b $(ALPINE_BRANCH) -m $(ALPINE_MIRROR)

	dpkg -x vendor/linux-image-$(KERNEL_VERSION)_$(KERNEL_REV_ARCH)_$(ARCH).deb $(ALPINE_CHROOT)
	mv $(ALPINE_CHROOT)/boot/vmlinuz-$(KERNEL_VERSION) $(ALPINE_CHROOT)/boot/zImage
	cp $(ALPINE_CHROOT)/usr/lib/linux-image-$(KERNEL_VERSION)/sun5i-r8-chip.dtb $(ALPINE_CHROOT)/boot/sun5i-r8-chip.dtb

	dpkg -x vendor/rtl8723bs-mp-driver-modules-$(KERNEL_VERSION)_$(MP_DRIVER_REV_ARCH)+$(KERNEL_REV_ARCH)_all.deb $(ALPINE_CHROOT)

	$(ALPINE_CHROOT)/enter-chroot -u root <<-CHROOT
		set -x

		apk add sudo ca-certificates wpa_supplicant wireless-tools wireless-regdb iw kbd-bkeymaps chrony tzdata openssh dbus avahi

		setup-hostname $(SYSTEM_HOSTNAME)
		echo "127.0.0.1    $(SYSTEM_HOSTNAME) $(SYSTEM_HOSTNAME).localdomain" > /etc/hosts
		setup-keymap $(SYSTEM_KEYBOARD_LAYOUT) $(SYSTEM_KEYBOARD_VARIANT)

		setup-timezone -z $(SYSTEM_TIMEZONE)

		touch /etc/wpa_supplicant/wpa_supplicant.conf

		# Needed services
		for service in devfs dmesg mdev; do
			rc-update add \$$service sysinit
		done

		for service in modules sysctl hostname bootmisc swclock syslog wpa_supplicant networking; do
			rc-update add \$$service boot
		done

		for service in dbus sshd chronyd local avahi-daemon; do
			rc-update add \$$service default
		done

		for service in mount-ro killprocs savecache; do
			rc-update add \$$service shutdown
		done

		# more stuff
		apk add nano htop curl wget bash bash-completion
		sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd

		for GRP in spi i2c gpio; do
			addgroup --system \$$GRP
		done

		adduser -s /bin/bash -D $(SYSTEM_USER)

		for GRP in adm dialout cdrom audio users video games input gpio spi i2c netdev; do
		  adduser $(SYSTEM_USER) \$$GRP
		done

		echo "$(SYSTEM_USER):$(SYSTEM_USER)" | /usr/sbin/chpasswd
		echo "$(SYSTEM_USER) ALL=NOPASSWD: ALL" >> /etc/sudoers

		# Allow root login with no password.
		passwd root -d

		# Allow root login from serial.
		echo ttyS0 >> /etc/securetty
		echo ttyGS0 >> /etc/securetty

		# Make sure the USB virtual serial device is available.
		echo g_serial >> /etc/modules

		# Make sure wireless networking is available.
		echo 8723bs >> /etc/modules
		depmod $(KERNEL_VERSION)

		# These enable the USB virtual serial device, and the standard serial
		# pins to both be used as TTYs
		echo ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt102 >> /etc/inittab
		echo ttyGS0::respawn:/sbin/getty -L ttyGS0 115200 vt102 >> /etc/inittab
	CHROOT

	umount -l $(ALPINE_CHROOT)/proc
	umount -l $(ALPINE_CHROOT)/sys
	umount -l $(ALPINE_CHROOT)/dev

	rm -rf $(ALPINE_CHROOT)/var/lib/apt/lists/*
	rm -rf $(ALPINE_CHROOT)/var/cache/apk/*
	rm -rf $(ALPINE_CHROOT)/root/*
	rm -rf $(ALPINE_CHROOT)/bootstrap/
	rm $(ALPINE_CHROOT)/enter-chroot
	rm $(ALPINE_CHROOT)/etc/resolv.conf
	rm $(ALPINE_CHROOT)/env.sh
	find $(ALPINE_CHROOT) -iname "*-" -delete
	find $(ALPINE_CHROOT) -iname "*~" -delete

vendor/linux-image-%.deb:
	cd vendor &&  wget $(CHIP_APT_REPO)/pool/main/l/linux-$(KERNEL_VERSION)/$(notdir $@)

vendor/rtl8723bs-mp-driver-modules-%.deb:
	cd vendor &&  wget $(CHIP_APT_REPO)/pool/main/r/rtl8723bs-mp-driver/$(notdir $@)

clean:
	rm -Rf dist/*

.INTERMEDIATE: dist/ubinize.cfg dist/rootfs.ubifs dist/rootfs.ubi dist/flash.cmd
