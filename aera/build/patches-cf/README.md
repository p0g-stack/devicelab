# Devicelab-only fakes

Patches here make AERA run on Cuttlefish by faking or stubbing things
(a health HAL stand-in, Cuttlefish-only hacks). They are **not** fixes and
are never offered upstream; real fixes go to flutter-aera's series in
`../patches/`. `build.sh` applies these after that series (set
`AERA_PATCHES_CF=` to leave them out) and lists each as `fake` in
BUILD-INFO. Each patch's subject starts with `FAKE:`.

Layout as in `../patches/`: `<project path>/NNNN-*.patch`.
