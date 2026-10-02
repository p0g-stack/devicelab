# Patches on the pinned AERA tree

One directory per project path, `git format-patch` files applied in name
order with `git am` after sync, e.g.

```
patches/bootable/recovery/0001-plugin_api-host-api-3-pixel-surface.patch
```

The Host API 3 series under `bootable/recovery/` is owned by the flutter-aera
thread, and so is the LVGL series under `external/lvgl/`
(flutter-aera `third_party/aera/lvgl-patches/`); drop updated patches here (or point `AERA_PATCHES` at another
directory) and rerun the build.

Device-tree patches live under the tree's checkout path, e.g.
`patches/device/oneplus/infiniti/`. The AERA manifest leaves device trees
commented out, so they apply only on a build machine that adds the tree as a
local manifest (at the path above, pinned to the commit the patch was made
against); `build.sh` skips them elsewhere. `device/oneplus/infiniti/` is made
against `android_device_oneplus_infiniti-AERA` `0d5f0b6`; see
`../../DEVICE-TREES.md`.
