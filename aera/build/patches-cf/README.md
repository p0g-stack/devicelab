# Devicelab-only fakes

Patches here make AERA run on Cuttlefish by faking or stubbing things
(a health HAL stand-in, Cuttlefish-only hacks). They are **not** fixes and
are never offered upstream; real fixes go to the p0g-stack recovery branch
that `../pins.xml` pins. `build.sh` applies these after `patches/` (set
`AERA_PATCHES_CF=` to leave them out) and lists each as `fake` in
BUILD-INFO. Each patch's subject starts with `FAKE:`.

Empty at this pin: the adbd fake that keeps adbd running on Cuttlefish
whatever the USB config is now a commit in that branch, so it cannot be
applied twice.

Layout as in `../patches/`: `<project path>/NNNN-*.patch`.
