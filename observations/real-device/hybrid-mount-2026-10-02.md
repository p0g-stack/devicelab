# Real device: demo v0.1.39 app plane under Hybrid Mount (2026-10-02)

Yuv's phone (OnePlus, ColorOS-style /my_* partitions), KernelSU Next, metamodule Hybrid Mount 4.2.0-1815
(`/data/adb/metamodule -> /data/adb/modules/hybrid_mount`), config `default_mode = "magic"`, `mountsource = "KSU"`.
Other modules: rezygisk, zygisk_vector, fake_bl_efisp, oplus_nr_fix.

Result: WORKS, no setting needed, module unchanged.
- Installer added `product -> ./system/product` in the module dir (Hybrid Mount metainstall.sh).
- Magic mount: tmpfs `KSU` over /product/app, per-file binds; `/product/app/WebuiApi_demo/WebuiApi_demo.apk`
  bound from Hybrid Mount's ext4 image (/dev/block/loop48), label u:object_r:system_file:s0.
- `pm path com.webui.api.demo` -> /product/app/WebuiApi_demo/WebuiApi_demo.apk, versionName 0.53.0-webui.6, flags SYSTEM.
- App has no launcher activity: visible only in Settings > Apps with system apps shown. "Not installed" report was the drawer.
- `pm` fails with "Failed transaction (2147483646)" when its stdout is redirected to a file under su (system_server cannot write the fd); run it to the terminal.

Implication for the managers lab: the emulator's "Hybrid Mount 6.2.2 installs but app NOT mounted"
(managers-2026-10-01.md) is most likely a lab artifact (KernelSU late-load mode / soft reboot), not a Hybrid Mount limitation.
Our module layout (system/product/app/...) is the standard one and needs no metamodule knowledge.

## Update 19:42Z: app plane dead under default "Umount modules" (real cause of Share timeout)

Share/Toast timed out ("did not answer within 10 s"); the app process never stayed up, even `am start` of its main
activity (LaunchState UNKNOWN, no window). Cause: KernelSU's kernel umount. For a zygote child whose uid has no root and
no own profile, `ksu_uid_should_umount` = default non-root profile umount_modules (true by default), and the kernel
detaches every try_umount entry; Hybrid Mount registers its mounts (disable_umount = false), so the app loses its own
APK (/product/app/WebuiApi_demo is a module mount). Yuv gave com.webui.api.demo a custom profile with "Umount modules"
OFF in KernelSU Next -> app launches and answers. Any module-shipped app is affected; lab Mountify runs did not hit it
(Mountify apparently does not register try_umount, or lab default differs; unverified).
Fix options (card to Yuv): module sets its own app's non-root profile umount_modules=false after boot
(KSU_IOCTL_SET_APP_PROFILE; KernelSU Next `ksud profile set` JSON since 146455c 2026-09-20, upstream KernelSU has no CLI);
or pm install; or document the toggle.
Also: `am`/`pm` under su in Termux may print nothing or fail when stdout is a file; use /system/bin/am.
