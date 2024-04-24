# Rockchip bootloader FIP images for Orangepi 5 / 5B / 5 plus

**This project is not affiliated with OrangePi, it's my personal project and I purchased all the needed hardware by myself.**

This is only bootloader image, the bootloader should work regardless of the distro you're using. However, some distros tend to hack their own u-boot booting scheme and does not follow [U-Boot Standard Boot](https://docs.u-boot.org/en/latest/develop/bootstd.html), including OPi's official images, and many of those popular "ARM-friendly distros". 

So, unless you know the distro you would boot with these bootloader images stick to the mainline booting scheme, you should not rely on the images here. And if you insist on doing so, remember to adapt the booting configuration to the standard boot scheme.

If you're using my pre-built [Arch Linux ARM images](https://github.com/7Ji/orangepi5-archlinuxarm) then the bootloader should work just fine, as I always follow the standard boot scheme.

## Download

You can download rkloaders for opi5 family from the [nightly release page](https://github.com/7Ji/orangepi5-rkloader/releases/tag/nightly), they're built and pushed everyday and always contain the latest BL31, DDR and u-boot.

The downloaded images are compressed with gzip, and you'll need to decompress them before using them.

## Image Layout
Vendor images (same image for SPI/SD/eMMC) and mainline SPI image are all 4MiB without compression. They should be stored at the beginning of your SPI/SD/eMMC, without offset. 

Mainline SD/eMMC image is 13 MiB without compression (same image for SD/eMMC, both with `-sd` suffix), it shall be stored at the beginning of your SD or eMMC user area.

All of the images contain GPT partition tables and some reserved partitions in them to hint on areas not safe to allocate partitions on. But the partitions are only for hint and only needed on SD/eMMC. Erasing them is OK, as long as you keep the unsafe areas intact.

_Specially, there are dedicated idbloader and u-boot.itb images that you'll only need if you want to partition the SD/eMMC by yourself and then assemble the bootloader image in place._

For mainline SPI and vendor SPI/SD/eMMC images (4MiB), the GPT table is like the following:
```
label: gpt
label-id: CDE728D2-D8FE-2F4D-A850-0700BE72F4B3
device: rkloader-vendor-v2017.09-rk3588-orangepi_5_plus-r31.7f7ff61a-bl31-v1.45-ddr-v1.16.img
unit: sectors
first-lba: 34
last-lba: 8158
grain: 512
sector-size: 512

rkloader-vendor-v2017.09-rk3588-orangepi_5_plus-r31.7f7ff61a-bl31-v1.45-ddr-v1.16.img1 : start=          64, size=         960, type=8DA63339-0007-60C0-C436-083AC8230908, uuid=60AFF2C4-E5DE-5545-88DE-D0EAAA507162, name="idbloader"
rkloader-vendor-v2017.09-rk3588-orangepi_5_plus-r31.7f7ff61a-bl31-v1.45-ddr-v1.16.img2 : start=        1024, size=        6144, type=8DA63339-0007-60C0-C436-083AC8230908, uuid=52AB3A99-3B2E-F84C-97A4-39FDD1788763, name="uboot"
```
For mainline SD/eMMC image (13MiB), the GPT table is like the following:
```
label: gpt
label-id: AEA227E4-03AB-4121-A080-89F4E98C57A9
device: rkloader-mainline-master-orangepi-5-plus-rk3588-r92661.d097f9e129-bl31-v1.45-ddr-v1.16-sd-emmc.img
unit: sectors
first-lba: 64
last-lba: 26590
sector-size: 512

rkloader-mainline-master-orangepi-5-plus-rk3588-r92661.d097f9e129-bl31-v1.45-ddr-v1.16-sd-emmc.img1 : start=          64, size=        8000, type=8DA63339-0007-60C0-C436-083AC8230908, uuid=87D7DE44-9EDE-468C-A5D7-C3D2F8598F6D, name="idbloader"
rkloader-mainline-master-orangepi-5-plus-rk3588-r92661.d097f9e129-bl31-v1.45-ddr-v1.16-sd-emmc.img2 : start=       16384, size=        8192, type=8DA63339-0007-60C0-C436-083AC8230908, uuid=9F496685-FAC8-4814-80C1-21589BE2537D, name="uboot"
```
As long as you don't create a new table, the existing partitions should prevent you from creating partitions on the unsafe areas.

In fact, these partitions are allocated way larger than their underlying data. For 4MiB, the actual unsafe area is only the first ~2MiB, and for 13MiB, ~9.3MiB. I created them larger than actual data for future-proof. 

In other word, truncating the image, or re-creating partitions overlapping the existing partitions are both OK, as long as the underlying data are intact.

## Installation

You should write the decompressed image into SPI, SD or eMMC, without any offset. For SPI, the image might seem larger but as the data is only 9.1MiB you don't need to worry about the truncated tail.

As long as there's at least one device containing rkloader then your device should boot, no matter it's the SD card, the eMMC, or the SPI flash. And as all of the opi5 family came with an on-board 16MiB/128Mb SPI flash, I'd always recommend using that for rkloader, to save space on your main system drive.

### Writing to SPI flash
**WARNING: Do not use the mainline image on SPI yet, I've omitted the spi building steps and the builder only built SD/eMMC images for mainline for fast testing purposes, this would be fixed later but not on top of my todo list. The vendor images still work as how they worked (on SPI/SD/eMMC).**

Check the user manual of opi5/5b/5plus if you want to write under another Windows/Linux device.

On the device itself, do it like follows:
1. Zero-out the SPI flash before writing to it (`flash_erase` is from package `mtd-utils`):
    ```
    flash_erase /dev/mtd0 0 0
    ```
2. Write the rkloader image to it:
   ```
   dd if=rkloader.img of=/dev/mtdblock0 bs=4K
   ```
Note that:
 - Writting to SPI flash is very slow, ~60KiB/s, take patience
 - The erase block size of the on-board SPI flash is 4K, you can omit `bs=4K` arg but the default 512 block size would result in 8 writes to the same block for one 4K chunk of data, killing its lifespan very fast.

#### Writing to other block devices
It's always recomended to write the rkloader before you partition the drive, as they contain partition hints on unusable space:
```
# sfdisk -d rkloader-3588-orangepi-5-bl31-v1.38-ddr-v1.11-uboot-70b68713.img
label: gpt
label-id: A56EECCE-C819-4B6A-9C8A-3DD2DA5A5581
device: rkloader-3588-orangepi-5-bl31-v1.38-ddr-v1.11-uboot-70b68713.img
unit: sectors
first-lba: 34
last-lba: 8158
grain: 512
sector-size: 512

rkloader-3588-orangepi-5-bl31-v1.38-ddr-v1.11-uboot-70b68713.img1 : start=          64, size=         960, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=ED109328-4281-42F8-9F41-E229F38C4973, name="idbloader"
rkloader-3588-orangepi-5-bl31-v1.38-ddr-v1.11-uboot-70b68713.img2 : start=        1024, size=        6144, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=2162DE6C-AE90-4808-BC19-570D524FCB48, name="uboot"
```
As such, just write the image to your target image, then allocate your partitions with 4 MiB / 8192 sectors offset starting from partition 3, and you're safe from corrupting the rkloader.

Your result partition table would be like the following:
```
# sfdisk -d /dev/mmcblk1
label: gpt
label-id: BB3FDB43-B5B7-4246-A919-BE81F982EE19
device: /dev/mmcblk1
unit: sectors
first-lba: 34
last-lba: 488554462
sector-size: 512

/dev/mmcblk1p1 : start=          64, size=         960, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=2AFE2EC3-BF29-4066-8287-E99F2C85EE09, name="idbloader"
/dev/mmcblk1p2 : start=        1024, size=        6144, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=6256FD76-DA9F-4DDE-B499-374B29A6B65B, name="uboot"
/dev/mmcblk1p3 : start=        8192, size=      204800, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=1B233D55-9FFA-44B7-BBDF-0DDA8B9E7C51
/dev/mmcblk1p4 : start=      212992, size=   488339456, type=B921B045-1DF0-41C3-AF44-4C6F280D3FAE, uuid=3125F455-A424-44F0-ACD9-1843331FA001
```
Specially, mark your boot partition (in this case partition 3) as EFI system partition (`type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B`, in fdisk it's part type `1` when using `t` command), so the bootloader would know to find boot configs/kernel/initramfs from it. 

In your system, the partition would be mounted like this:
```
NAME         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
mmcblk1      179:0    0   233G  0 disk 
├─mmcblk1p1  179:1    0   480K  0 part 
├─mmcblk1p2  179:2    0     3M  0 part 
├─mmcblk1p3  179:3    0   100M  0 part /boot
└─mmcblk1p4  179:4    0 232.9G  0 part /
```

#### Write to already partitioned drive
This is not recomended as the partition table inside the rkloader image would overwrite your existing part table. But you should still be able to work around it as long as your partitions start after the fist 4MiB:
 1. Dump your existing partitions with `sfdisk -d`:
    ```
    sfdisk -d /dev/mmcblk1 > old_parts.log
    ```
 2. Write the rkloader
    ```
    dd if=rkloader.img of=/dev/mmcblk1 bs=1M count=4
    ```
    _If `of` is a disk image, also add `conv=notrunc`_
 3. Get the current partitions
    ```
    sfdisk -d /dev/mmcblk1 > loader_parts.log
    ```
 4. Modify the current partitions, append your existing partitions in `old_parts.log` after first two parts in `loader_parts.log`, to get your new `new_parts.log`
 5. Apply the new partition table:
    ```
    sfdisk /dev/mmcblk1 < new_parts.log
    ```
