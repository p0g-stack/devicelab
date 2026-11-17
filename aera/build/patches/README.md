# Patches on the pinned AERA tree

One directory per project path, `git format-patch` files applied in name
order with `git am` after sync, e.g. `patches/system/core/0001-*.patch`.

AERA's own carried series is not here: `bootable/recovery` and
`external/lvgl` are pinned in `../pins.xml` to p0g-stack branches that
inherit AERA upstream and already carry the rebased patches
(`rebase-1cabc509`, `rebase-626794146`; the pins' comment names the
upstream commits). Patches are not applied twice, and a series is changed by
pushing to those branches and moving the pin, not by dropping files here.
The Host API 3 pixel-plugin series is not part of that set: upstream's
Host API 2 now provides the surface, text-field and Files-selection
interfaces it used to add.

Device-tree patches live under the tree's checkout path, e.g.
`patches/device/oneplus/infiniti/`. The AERA manifest leaves device trees
commented out, so they apply only on a build machine that adds the tree as a
local manifest (at the path above, pinned to the commit the patch was made
against); `build.sh` skips them elsewhere. `device/oneplus/infiniti/` is made
against `android_device_oneplus_infiniti-AERA` `0d5f0b6`; see
`../../DEVICE-TREES.md`.
