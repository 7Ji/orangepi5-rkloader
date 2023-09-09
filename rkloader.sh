#!/bin/bash -e
init_repo() { # 1: dir, 2: url, 3: branch
    if [[  -z "$1$2" ]]; then
        echo "Dir and URL not set"
        return 1
    fi
    rm -rf "$1"
    mkdir "$1"
    mkdir "$1"/{objects,refs}
    echo 'ref: refs/heads/'"$3" > "$1"/HEAD
    printf '[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = true\n[remote "origin"]\n\turl = %s\n\tfetch = +refs/heads/%s:refs/heads/%s\n' \
        "$2" "$3" "$3" > "$1"/config
}

# Sync sources
uboot_branch=v2017.09-rk3588
git_urls=('https://github.com/'{'armbian/rkbin','orangepi-xunlong/u-boot-orangepi'}'.git')
git_branches=('master' "${uboot_branch}")
i=0
for git_url in "${git_urls[@]}"; do
    git_dir=${git_url##*/}
    if [[ ! -d "${git_dir}" ]]; then
        init_repo "${git_dir}" "${git_url}" "${git_branches[$i]}"
    fi
    if [[ ! -d "${git_dir}" ]]; then
        echo "Failed to prepare local git dir ${git_dir} from ${git_url}"
        exit 1
    fi
    echo "Updating '${git_dir}' <= '${git_url}'"
    git --git-dir "${git_dir}" remote update --prune
    i=$(( i + 1 ))
done

# Deploy toolchain
toolchain=gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu
if [[ ! -d ${toolchain} ]]; then
    echo "Deploying toolchain ${toolchain}"
    for mirror in \
        'https://redirect.armbian.com' \
        'https://mirrors.tuna.tsinghua.edu.cn/armbian-releases'
    do
        rm -rf "${toolchain}.temp"
        mkdir "${toolchain}.temp"
        if wget "${mirror}/_toolchain/${toolchain}.tar.xz" -O - |
            tar -C "${toolchain}.temp" --strip-components 1 -xJ; then break; fi
    done
    mv "${toolchain}"{.temp,}
fi

# Get latest bl31 and ddr
rm -rf rkbin
mkdir rkbin
git --git-dir rkbin.git --work-tree rkbin checkout -f master
rkbin=$(readlink -f rkbin)
bl31=$(ls "${rkbin}"/rk35/rk3588_bl31_* | tail -n 1)
ddr=$(ls "${rkbin}"/rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_* | tail -n 1)
bl31_ver=${bl31##*bl31_}
bl31_ver=${bl31_ver%%.elf}
ddr_ver=${ddr##*ddr_lp4_2112MHz_lp5_2736MHz_}
ddr_ver=${ddr_ver%%.bin}

echo "Latest BL31: ${bl31_ver}"
echo "Latest DDR: ${ddr_ver}"

# Get all configs for opi 5/ 5b/ 5 plus
rm -rf build
mkdir build
git --git-dir u-boot-orangepi.git --work-tree build checkout -f "${uboot_branch}"

configs=()
for config in 'build/configs/orangepi_5'*'_defconfig'; do
    config="${config##*orangepi_}"
    configs+=("${config%%_defconfig}")
done

echo "All configs for opi 5 series: ${configs[@]}"

# Get u-boot version
uboot_ver=$(git --git-dir u-boot-orangepi.git rev-parse --short "${uboot_branch}")
ver="bl31-${bl31_ver}-ddr-${ddr_ver}-uboot-${uboot_ver}"
{
    echo "u-boot version: $(git --git-dir u-boot-orangepi.git rev-parse "${uboot_branch}")"
    echo "BL31 version: ${bl31_ver}"
    echo "DDR version: ${ddr_ver}"
} > versions

# Build
table='label: gpt
first-lba: 34
start=64, size=960, type=8DA63339-0007-60C0-C436-083AC8230908, name="idbloader"
start=1024, size=6144, type=8DA63339-0007-60C0-C436-083AC8230908, name="uboot"'
mkdir -p out
outs=()
export ARCH=aarch64
export CROSS_COMPILE=aarch64-linux-gnu-
export PATH="$(readlink -f ${toolchain})/bin:$PATH"
for config in "${configs[@]}"; do
    out=out/rkloader-3588-orangepi-"${config}-${ver}".img
    outs+=("${out}")
    if [[ -f "${out}" ]]; then
        continue
    fi
    if [[ ! -d build ]]; then
        mkdir build
        git --git-dir u-boot-orangepi.git --work-tree build checkout -f "${uboot_branch}"
    fi
    echo "Configuring for ${config}"
    make -C build \
        orangepi_${config}_defconfig
    echo "Building for ${config}"
    make -C build \
        BL31="${bl31}" \
        -j$(nproc) \
        spl/u-boot-spl.bin u-boot.dtb u-boot.itb
    build/tools/mkimage -n rk3588 -T rksd -d ${ddr}:build/spl/u-boot-spl.bin build/idbloader.img
    tempout="${out}".temp
    truncate -s 4M "${tempout}"
    sfdisk "${tempout}" <<< "${table}"
    dd if=build/idbloader.img of="${tempout}" seek=64 conv=notrunc
    dd if=build/u-boot.itb of="${tempout}" seek=1024 conv=notrunc
    mv "${out}"{.temp,}
    rm -rf build
done

# Yeah this looks dumb but it's simpler than some more dumb loops
tar -cf out.tar "${outs[@]}"
rm -rf out
tar -xf out.tar