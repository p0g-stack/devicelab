# AERA Recovery for Cuttlefish x86_64 (p0g-stack/devicelab aera/). A lab
# target only: recovery ramdisk for direct-kernel boot on Cuttlefish.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
$(call inherit-product, device/p0g/aera_cf/device.mk)

PRODUCT_DEVICE := aera_cf
PRODUCT_NAME := twrp_aera_cf
PRODUCT_BRAND := p0g
PRODUCT_MODEL := AERA Cuttlefish x86_64
PRODUCT_MANUFACTURER := p0g
