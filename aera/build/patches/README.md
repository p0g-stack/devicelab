# Patches on the pinned AERA tree

One directory per project path, `git format-patch` files applied in name
order with `git am` after sync, e.g.

```
patches/bootable/recovery/0001-plugin_api-host-api-3-pixel-surface.patch
```

The Host API 3 series under `bootable/recovery/` is owned by the flutter-aera
thread; drop updated patches here (or point `AERA_PATCHES` at another
directory) and rerun the build.
