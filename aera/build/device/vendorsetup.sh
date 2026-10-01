# AERA's post-build script (vendor/recovery/AERA_A16.sh) reads these. Its
# prebuilts (busybox, bash, tar, sed, grep, xz, magiskboot, ...) exist only
# for arm/arm64, so the x86_64 lab image drops all of them: toybox/toolbox
# from the tree and mkbootimg/unpackbootimg (which do exist for x86_64).
FDEVICE="aera_cf"
if [ "$1" = "$FDEVICE" -o "$AERA_BUILD_DEVICE" = "$FDEVICE" -o -z "$AERA_BUILD_DEVICE$1" ]; then
	export LC_ALL="C"
	export AERA_BUILD_DEVICE="$FDEVICE"
	export AERA_DRASTIC_SIZE_REDUCTION=1
	export AERA_REMOVE_BASH=1
	export AERA_USE_BUSYBOX_BINARY=0
	export AERA_USE_DMSETUP=0
	export AERA_USE_PATCHELF_BINARY=0
	export AERA_USE_FSCK_EROFS_BINARY=0
	export AERA_DELETE_MAGISK_ADDON=1
	export AERA_DELETE_AROMAFM=1
	export AERA_VANILLA_BUILD=1
	export AERA_PRODUCT_PREFIX=AERA
	export AERA_BUILD_TYPE=Nightly  # aera_build.mk allows Alpha|Beta|Nightly|Stable
	export AERA_SETTINGS_ROOT_DIRECTORY=/data/recovery
	export AERA_MISCELLANEOUS_ROOT_DIRECTORY=/sdcard
	unset AERA_MAINTAINER_PATCH_VERSION
fi
