#!/bin/bash

set -e

EXTRACT_OTA=../../../prebuilts/extract-tools/linux-x86/bin/ota_extractor
MKDTBOIMG=../../../system/libufdt/utils/src/mkdtboimg.py
UNPACKBOOTIMG=../../../system/tools/mkbootimg/unpack_bootimg.py
ROM_ZIP=$1

error_handler() {
    if [[ -d $extract_out ]]; then
        echo "Error detected, cleaning temporal working directory $extract_out"
        rm -rf $extract_out
    fi
}

trap error_handler ERR

function usage() {
	echo "Usage: ./extract-files.sh <rom-zip>"
	exit 1
}

function get_path() {
	echo "$extract_out/$1"
}

function unpackbootimg() {
	$UNPACKBOOTIMG $@
}

function extract_ota() {
    $EXTRACT_OTA $@
}

if [[ ! -f $UNPACKBOOTIMG ]]; then
	echo "Missing $UNPACKBOOTIMG, are you on the correct directory?"
	exit 1
fi

if [[ ! -f $EXTRACT_OTA ]]; then
	echo "Missing $EXTRACT_OTA, are you on the correct directory and have built the ota_extractor target?"
	exit 1
fi

if [[ -z $ROM_ZIP ]] || [[ ! -f $ROM_ZIP ]]; then
	usage
fi

# Clean and create needed directories
for dir in ./vendor_dlkm ./system_dlkm ./vendor_ramdisk; do
    rm -rf $dir
    mkdir -p $dir
done

# Extract the OTA package
extract_out=$(mktemp -d)
echo "Using $extract_out as working directory"

echo "Extracting the payload from $ROM_ZIP"
unzip $ROM_ZIP payload.bin -d $extract_out

echo "Extracting OTA images"
extract_ota -payload $extract_out/payload.bin -output_dir $extract_out -partitions boot,dtbo,vendor_boot,vendor_dlkm,system_dlkm

# BOOT
echo "Extracting the kernel image from boot.img"
out=$extract_out/boot-out
mkdir $out

echo "Extracting at $out"
unpackbootimg --boot_img $(get_path boot.img) --out $out --format mkbootimg

echo "Done. Copying the kernel"
cp $out/kernel ./Image
echo "Done"

# vendor_ramdisk
echo "Extracting the ramdisk kernel modules and DTB"
out=$extract_out/vendor_ramdisk-out
mkdir $out

echo "Extracting at $out"
unpackbootimg --boot_img $(get_path vendor_boot.img) --out $out --format mkbootimg

echo "Done. Extracting the ramdisk"
mkdir $out/ramdisk
unlz4 $out/vendor_ramdisk00 $out/vendor_ramdisk
cpio -i -F $out/vendor_ramdisk -D $out/ramdisk

echo "Copying all ramdisk modules"
for module in $(find $out/ramdisk -name "*.ko" -o -name "modules.*"); do
	cp $module ./vendor_ramdisk/
done

# VENDOR_DLKM
echo "Extracting the dlkm kernel modules"
out=$extract_out/vendor_dlkm

echo "Extracting at $out"
fsck.erofs --extract="$out" $(get_path vendor_dlkm.img)

echo "Done. Extracting the vendor dlkm"

echo "Copying all vendor dlkm modules"
for module in $(find $out/lib -name "*.ko" -o -name "modules.*"  -o -name "system_dlkm.modules.blocklist"); do
	cp $module ./vendor_dlkm/
done

# SYSTEM_DLKM
echo "Extracting the dlkm kernel modules"
out=$extract_out/system_dlkm

echo "Extracting at $out"
fsck.erofs --extract="$out" $(get_path system_dlkm.img)

echo "Done. Extracting the system dlkm"

echo "Copying all system dlkm modules"
cp -r $out/lib/modules/6.1* ./system_dlkm/

# Extract DTBO and DTBs
echo "Extracting DTBO and DTBs"

curl -sSL "https://raw.githubusercontent.com/PabloCastellano/extract-dtb/master/extract_dtb/extract_dtb.py" > ${extract_out}/extract_dtb.py

# Copy DTB
python3 "${extract_out}/extract_dtb.py" "${extract_out}/vendor_ramdisk-out/dtb" -o "${extract_out}/dtbs" > /dev/null
find "${extract_out}/dtbs" -type f -name "*.dtb" \
    -exec cp {} ./dtbs/ \; \
    -exec printf "  - dtbs/" \; \
    -exec basename {} \;

cp -f "${extract_out}/dtbo.img" ./dtbo.img
echo "Done"

rm -rf $extract_out
echo "Extracted files successfully"
