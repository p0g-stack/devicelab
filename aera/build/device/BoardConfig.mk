# Cuttlefish x86_64, recovery ramdisk only. Cuttlefish's own kernel and
# vendor ramdisk (virtio modules) are combined with this ramdisk at boot by
# aera/cuttlefish/boot-aera.sh, as a bootloader would.
DEVICE_PATH := device/p0g/aera_cf
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
BUILD_BROKEN_PLUGIN_VALIDATION := soong-libaosprecovery_defaults soong-libguitwrp_defaults soong-libminuitwrp_defaults soong-vold_defaults

TARGET_ARCH := x86_64
TARGET_ARCH_VARIANT := x86_64
TARGET_CPU_ABI := x86_64
TARGET_CPU_VARIANT := generic
TARGET_BOARD_PLATFORM := aera_cf
TARGET_BOOTLOADER_BOARD_NAME := aera_cf
TARGET_NO_BOOTLOADER := true
TARGET_NO_KERNEL := true
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_RAMDISK_USE_LZ4 := true

BOARD_RECOVERYIMAGE_PARTITION_SIZE := 134217728
BOARD_FLASH_BLOCK_SIZE := 131072
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
TARGET_COPY_OUT_VENDOR := vendor

PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
AERA_THEME := portrait_hdpi
AERA_FRAMERATE := 60
# AERA lays pages out on a 1440x3168 design canvas; without adaptive
# resolution it is drawn 1:1 on this 720-wide panel and overflows (landscape
# Home bar cut at both edges, shade text overlaps). Screen height in 1080-wide
# units: 1348*1080/720 = 2022 (logical 1440x2696); status bar at AERA's default.
AERA_UI_ADAPTIVE_RESOLUTION := true
AERA_SCREEN_H := 2022
AERA_STATUS_H := 124
AERA_NO_SCREEN_BLANK := true
# Required by aera_build.mk; Cuttlefish has no backlight, and minuitwrp skips
# the write when the path does not open.
AERA_MAX_BRIGHTNESS := 255
AERA_BRIGHTNESS_PATH := /sys/class/backlight/cf/brightness
AERA_EXCLUDE_APEX := true
AERA_USE_TOOLBOX := true
TARGET_USES_LOGD := true
AERA_INCLUDE_LOGCAT := true
AERA_DEFAULT_LANGUAGE := en
AERA_DEVICE_VERSION := Cuttlefish_x86_64
AERA_EXCLUDE_DEFAULT_USB_INIT := true

# libandroidfw (linked by the recovery binary) needs libincfs, but AERA's
# prebuilt/Android.mk packs libincfs only for FBE crypto builds; without
# it the recovery exits at link time (aera/DEFICIENCIES.md, D1).
TARGET_RECOVERY_DEVICE_MODULES += libincfs
RECOVERY_LIBRARY_SOURCE_FILES += $(TARGET_OUT_SHARED_LIBRARIES)/libincfs.so
