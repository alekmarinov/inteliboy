#!/bin/bash
set -e
echo "Building linux kernel for InteliBoy.."
echo "Approximate build time: about 12 SBU"
echo "Required disk space: about 1700 MB"

# 10.3. Linux, InteliBoy variant
# The same kernel source as 10.3-make-linux-kernel.sh built against its own
# configuration, so the appliance can diverge from the desktop distros without
# either of them having to agree with the other.
#
# Why a second recipe rather than a switch in the first: the kernel is listed in
# distros/core/packages.list, which every distro includes, and the package store
# is keyed on this script's name. One recipe cannot produce two packages, and
# changing the shared one puts four working images at risk to serve one new
# distro. Duplication is the cheaper trade.
#
# CONFIG_LOCALVERSION is "-inteliboy" in the config, so the kernel image, the
# modules directory and the map file all carry that suffix and the two kernels
# can sit in the same build tree without overwriting each other.
#
# The configuration starts as a copy of the working 6.16.1 one rather than a
# trimmed-down build. Everything the renderer needs is already enabled there -
# DRM, i915 built in, nouveau as a module, evdev, ALSA - and a kernel trimmed
# without measuring is how an image stops booting for a reason that takes a day
# to find. Trim it once boot time has been measured on the real machine.
#
# The divergences are applied below with scripts/config rather than baked into
# the stored file, so what this distro wants is one readable list.
#
# One of them is worth recording because it is exactly what a per-distro
# kernel buys. CONFIG_DEBUG_STACK_USAGE makes the
# kernel print 'sed (120) used greatest stack depth' as processes exit. On a
# desktop that is invisible among the rest of the boot log; here, with the
# console quietened and nothing else on screen, those two lines were the only
# thing between the firmware logo and the renderer. No kernel command line
# silences them - the messages come from the kernel's own debug code, so the
# only place to turn them off is the configuration.
#
# BUILD_REQUIRES: 8.29-make-gcc 8.20-make-binutils 8.69-make-make 8.14-make-bc
# BUILD_REQUIRES: 8.15-make-flex 8.34-make-bison 8.43-make-perl 8.58-make-kmod
# BUILD_REQUIRES: 8.49-make-libelf 8.48-make-openssl
# RUNTIME_REQUIRES: 8.58-make-kmod
# DISTRO_ONLY: inteliboy names this in its own packages.list; no other distro
# should be handed a second kernel

VER=$(ls /sources/linux-*.tar.xz | sed 's/^[^-]*-//' | sed 's/[^0-9]*$//')
SUFFIX=inteliboy

rm -rf /tmp/linux-$SUFFIX
tar -xf /sources/linux-*.tar.xz -C /tmp/ \
    && mv /tmp/linux-[0-9]* /tmp/linux-$SUFFIX \
    && pushd /tmp/linux-$SUFFIX \
    || exit 1

chown -R 0:0 .
make mrproper
cp /sources/kernel-$SUFFIX-*.config .config

# What InteliBoy wants that the desktop configuration does not, stated as
# intent rather than as a diff against 5390 lines. scripts/config sets the
# symbols and 'make olddefconfig' resolves what they depend on - editing the
# file by hand does not, and a symbol whose parent is off is silently dropped
# rather than reported.
./scripts/config --file .config \
    `# Sound. SND_HDA_INTEL alone is only the PCI controller; without a codec` \
    `# driver it finds the chip and cannot drive it, so there are no PCM` \
    `# devices at all - no speakers and no microphone, since capture and` \
    `# playback share the codec. GENERIC is the fallback that works when the` \
    `# specific driver is wrong.` \
    `#` \
    `# Built in, not modules, and that matters here: modules are loaded by` \
    `# udev, and the renderer starts before udev on purpose. As modules the` \
    `# sound card would not exist yet when it opens ALSA. Built in, the card` \
    `# is there at kernel init like the DRM device is.` \
    --enable CONFIG_SND_HDA_GENERIC \
    --enable CONFIG_SND_HDA_CODEC_REALTEK \
    --enable CONFIG_SND_HDA_CODEC_HDMI \
    --module CONFIG_SND_USB_AUDIO \
    `# Camera. MEDIA_SUPPORT is the parent of the whole media subsystem: with` \
    `# it off, VIDEO_DEV and USB_VIDEO_CLASS do not exist as symbols to set.` \
    `# uvcvideo is what a built-in laptop webcam speaks.` \
    --enable CONFIG_MEDIA_SUPPORT \
    --enable CONFIG_MEDIA_CAMERA_SUPPORT \
    --enable CONFIG_MEDIA_USB_SUPPORT \
    --module CONFIG_USB_VIDEO_CLASS \
    `# The two lines the kernel prints as processes exit. Nothing on the` \
    `# command line silences them; they come from the kernel's own debug code.` \
    --disable CONFIG_DEBUG_STACK_USAGE

make olddefconfig

make
make modules_install

# NOTE plain 'cp -vf', not 'cp -ivf': the -i prompts when the file is already
# there, which -f does not override, and with no terminal the prompt is read as
# a no - so a rebuild would silently keep the old kernel.
cp -vf arch/x86/boot/bzImage /boot/vmlinuz-$VER-$SUFFIX
cp -vf System.map /boot/System.map-$VER-$SUFFIX
cp -vf .config /boot/config-$VER-$SUFFIX

popd
rm -rf /tmp/linux-$SUFFIX

# The image is only bootable if these exist under the name the config asked for.
test -f /boot/vmlinuz-$VER-$SUFFIX
test -d /lib/modules/$VER-$SUFFIX
echo "kernel $VER-$SUFFIX installed"
