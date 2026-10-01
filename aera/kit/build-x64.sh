#!/usr/bin/env bash
# x86_64 flavour of flutter-aera's runtime kit, for Cuttlefish (x86_64 only
# under KVM on GitHub runners). Same layout as kit-3.47.5 (spec/aerap.md),
# but Mesa is softpipe + virgl (virtio-gpu) instead of Zink/Turnip, and the
# simulator host is built static so it runs inside a bionic recovery.
#   build-x64.sh OUT        -> OUT/kit (payload tree minus app), OUT/aera-host-sim
# Needs: Rust, meson>=1.4, ninja, mako, libdrm-dev, the Flutter build deps.
set -euo pipefail
FA_REV=${FA_REV:-c9414a50a06305607ff89db9c5baa7eb44a11f35}   # p0g-stack/flutter-aera
out=$(realpath -m "${1:?usage: build-x64.sh OUT}"); mkdir -p "$out"
work=$out/work; mkdir -p "$work"
fa=$work/flutter-aera
if [ ! -d "$fa" ]; then
  git init -q "$fa"; git -C "$fa" fetch -q --depth 1 https://github.com/p0g-stack/flutter-aera "$FA_REV"
  git -C "$fa" checkout -q FETCH_HEAD
fi

# Mesa: the pinned tarball and patch from flutter-aera, x86 driver set.
if [ ! -d "$work/mesa/usr/lib" ]; then
  curl -fsSL -o "$work/mesa.tar.xz" https://archive.mesa3d.org/mesa-26.2.2.tar.xz
  echo "eeb29ca7e56cfaa8e8a79538dcf834e3b18e501c31bef5145e959ea437cc4216  $work/mesa.tar.xz" | sha256sum -c -
  tar -C "$work" -xf "$work/mesa.tar.xz"
  (cd "$work/mesa-26.2.2" && patch -p1 < "$fa/third_party/mesa/mesa-26.2.2-zink-kgsl-surfaceless.patch" \
    && meson setup build --wrap-mode=nodownload --prefix=/usr --libdir=lib \
      -Dbuildtype=release -Db_ndebug=true -Dplatforms= -Degl=enabled -Dgles1=disabled \
      -Dgles2=enabled -Dopengl=true -Dglx=disabled -Dgbm=disabled -Dglvnd=disabled \
      -Dgallium-drivers=softpipe,virgl -Dvulkan-drivers= \
      -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled \
      -Dbuild-tests=false -Dvideo-codecs= -Dvulkan-layers= -Dtools= -Dzstd=enabled \
      -Dexpat=enabled -Dteflon=false >/dev/null \
    && ninja -C build >/dev/null && DESTDIR="$work/mesa" ninja -C build install >/dev/null)
fi

(cd "$fa" && cargo build -q --release -p flutter-aera \
  && RUSTFLAGS="-C target-feature=+crt-static" cargo build -q --release -p aera-plugin -p aera-host-sim \
       --target x86_64-unknown-linux-gnu --target-dir target/static)
st=$fa/target/static/x86_64-unknown-linux-gnu/release
for b in aera-plugin aera-host-sim; do file "$st/$b" | grep -q 'statically linked\|static-pie' || { file "$st/$b"; exit 1; }; done
cp "$st/aera-host-sim" "$out/aera-host-sim"

"$fa/ci/fetch-engine.sh" "$work/engine" x64
# assemble-kit.py is written for arm64; same steps with the x86_64 loader
# and no Vulkan/Turnip.
sed -e 's/ld-linux-aarch64.so.1/ld-linux-x86-64.so.2/' \
    -e 's/DLOPENED = .*/DLOPENED = ["libEGL.so.1", "libGLESv2.so.2"]/' \
    -e '/Turnip.s ICD/,/write_text(json.dumps(icd/d' "$fa/ci/assemble-kit.py" > "$work/assemble-kit-x64.py"
jq -n --arg rev "$FA_REV" '{kit: 1, arch: "x64", mode: "debug", flutter: "3.47.5",
  engine_revision: "af7e796e161ae0bb1ff0758c71a7105418bd9ded", mesa: "26.2.2 softpipe+virgl",
  flutter_aera_commit: $rev, built_by: "p0g-stack/devicelab aera/kit/build-x64.sh"}' > "$work/kit.json"
rm -rf "$out/kit"
python3 "$work/assemble-kit-x64.py" --out "$out/kit" --embedder "$fa/target/release/aera-flutter" \
  --launcher "$st/aera-plugin" --engine "$work/engine/embedder/libflutter_engine.so" \
  --icu "$work/engine/icudtl.dat" --mesa "$work/mesa" \
  --sysroot /usr/lib/x86_64-linux-gnu --sysroot /lib/x86_64-linux-gnu --sysroot /lib64 \
  --ca-bundle /etc/ssl/certs/ca-certificates.crt --pins "$work/kit.json"
rmdir "$out/kit/usr/share/vulkan/icd.d" "$out/kit/usr/share/vulkan" 2>/dev/null || true
ls -la "$out/kit/usr/lib" | head -50
