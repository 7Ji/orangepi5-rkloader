#!/bin/bash -e

uboot_vendor_repo_url=${uboot_vendor_repo_url:-https://github.com/orangepi-xunlong/u-boot-orangepi.git}
uboot_vendor_branch=${uboot_vendor_branch:-v2017.09-rk3588}

uboot_mainline_repo_url=${uboot_mainline_repo_url:-https://github.com/u-boot/u-boot}
uboot_mainline_branch=${uboot_mainline_branch:-master}

rkbin_repo_url=${rkbin_repo_url:-https://github.com/armbian/rkbin.git}
rkbin_branch=${rkbin_branch:-master}

configs_vendor=(${configs_vendor:-orangepi_5b orangepi_5 orangepi_5_plus orangepi_5_sata})
configs_mainline=(${configs_mainline:-orangepi-5-plus-rk3588 orangepi-5-rk3588s})

toolchain_vendor=${toolchain_vendor:-gcc-linaro-7.4.1-2019.02-x86_64_aarch64-linux-gnu}

armbian_mirror=${armbian_mirror:-https://redirect.armbian.com}

gpt_vendor='label: gpt
first-lba: 34
start=64, size=960, type=8DA63339-0007-60C0-C436-083AC8230908, name="idbloader"
start=1024, size=6144, type=8DA63339-0007-60C0-C436-083AC8230908, name="uboot"'

# The image is 9.1 MiB, for safety we have 16 MiB, 
gpt_mainline='label: gpt
first-lba: 64
start=64, size=32704, type=8DA63339-0007-60C0-C436-083AC8230908, name="uboot"'


# Init a repo, we do this in Bash world because we only need minimum config
init_repo() { # 1: git dir, 2: url, 3: branch
    if [[  -z "$1$2" ]]; then
        echo "Dir and URL not set"
        return 1
    fi
    if [[ -z "$3" ]]; then
        local git_head='*'
    else
        local git_head="$3"
    fi
    rm -rf "$1"
    mkdir "$1"
    mkdir "$1"/{objects,refs}
    echo 'ref: refs/heads/'"${git_head}" > "$1"/HEAD
    printf '[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = true\n[remote "origin"]\n\turl = %s\n\tfetch = +refs/heads/%s:refs/heads/%s\n' \
        "$2" "${git_head}" "${git_head}" > "$1"/config
}

# Update a repo, init first if it could not be found
update_repo() { # 1: git dir, 2: url, 3: branch
    if [[ ! -d "$1" ]]; then
        init_repo "$1" "$2" "$3"
    fi
    if [[ ! -d "$1" ]]; then
        echo "Failed to prepare local git dir $1 from $2"
        return 1
    fi
    echo "Updating '$1' <= '$2'"
    if [[ "${gmr}" ]]; then
        echo "Trying 7Ji/git-mirrorer instance '${gmr}' before actual remote..."
        local git_ref=refs/heads/"$3"
        if git --git-dir "$1" fetch "${gmr}/${2#*://}" "+${git_ref}:${git_ref}" --prune; then
            i=$(( i + 1 ))
            return 0
        fi
    fi
    git --git-dir "$1" remote update --prune
}

# Update all repos
update_repos() {
    update_repo u-boot-vendor.git "${uboot_vendor_repo_url}" "${uboot_vendor_branch}"
    update_repo u-boot-mainline.git "${uboot_mainline_repo_url}" "${uboot_mainline_branch}"
    update_repo rkbin.git "${rkbin_repo_url}" "${rkbin_branch}"
}

deploy_toolchain_vendor() {
    if [[ ! -d toolchain-vendor ]]; then
        echo "Deploying toolchain ${toolchain_vendor}"
        rm -rf toolchain-vendor.temp
        mkdir toolchain-vendor.temp
        if wget "${armbian_mirror}/_toolchain/${toolchain_vendor}.tar.xz" -O - |
            tar -C toolchain-vendor.temp --strip-components 1 -xJ; then break; fi
        mv toolchain-vendor{.temp,}
    fi
}

prepare_rkbin() {
    rm -rf rkbin
    mkdir rkbin
    git --git-dir rkbin.git --work-tree rkbin checkout -f master
    rkbin=$(readlink -f rkbin)
    bl31=$(ls "${rkbin}"/rk35/rk3588_bl31_* | tail -n 1)
    ddr=$(ls "${rkbin}"/rk35/rk3588_ddr_lp4_2112MHz_lp5_2736MHz_* | tail -n 1)
    if [[ -z "${bl31}" ]]; then
        echo 'ERROR: Cannot find latest bl31'
        return 1
    fi
    if [[ -z "${ddr}" ]]; then
        echo 'ERROR: Cannot find latest ddr'
        return 1
    fi
}

generate_git_version() { #1 git dir, #2 branch
    printf 'r%s.%s' $(git --git-dir "$1" rev-list --count "$2") $(git --git-dir "$1" rev-parse --short "$2")
}

generate_version() {
    local bl31_ver=${bl31##*bl31_}
    bl31_ver=${bl31_ver%%.elf}
    local ddr_ver=${ddr##*ddr_lp4_2112MHz_lp5_2736MHz_}
    ddr_ver=${ddr_ver%%.bin}
    local suffix="-bl31-${bl31_ver}-ddr-${ddr_ver}"
    local uboot_vendor_ver=$(generate_git_version u-boot-vendor.git "${uboot_vendor_branch}")
    local uboot_mainline_ver=$(generate_git_version u-boot-mainline.git "${uboot_mainline_branch}")
    vendor_version="${uboot_vendor_ver}${suffix}"
    mainline_version="${uboot_mainline_ver}${suffix}"
    echo "**u-boot version (vendor)**: \`${uboot_vendor_ver}\`

**u-boot version (mainline)**: \`${uboot_mainline_ver}\`

**BL31 version**: \`${bl31_ver}\`

**DDR version**: \`${ddr_ver}\`

---

sha256sums
\`\`\`" > note.md
}

build_common() { #1 type #2 git branch #3 config
    local name=rkloader-"$1-$2-$3"-
    case "$1" in
    vendor) name+="${vendor_version}" ;;
    mainline) name+="${mainline_version}" ;;
    *)
        echo "ERROR: Unexpected type $1"
        return 1
        ;;
    esac
    name+='.img'
    echo "$1:$3:${name}.gz" >> out/list
    local out_raw=out/"${name}"
    local out="${out_raw}".gz
    outs+=("${out}")
    local report_name="u-boot ($1) for $3"
    if [[ -f "${out}" ]]; then
        echo "Skipped building ${report_name}"
        return 0
    fi
    mkdir build
    git --git-dir u-boot-"$1".git --work-tree build checkout -f "$2"
    echo "Configuring ${report_name}..."
    make -C build "$3"_defconfig
    echo "Building ${report_name}..."
    rm -f "${out_raw}"
    case "$1" in
    vendor)
        make -C build \
            BL31="${bl31}" \
            -j$(nproc) \
            spl/u-boot-spl.bin u-boot.dtb u-boot.itb
        build/tools/mkimage -n rk3588 -T rksd \
            -d "${ddr}":build/spl/u-boot-spl.bin \
            build/idbloader.img
        truncate -s 4M "${out_raw}"
        sfdisk "${out_raw}" <<< "${gpt_vendor}"
        dd if=build/idbloader.img of="${out_raw}" seek=64 conv=notrunc
        dd if=build/u-boot.itb of="${out_raw}" seek=1024 conv=notrunc
        ;;
    mainline)
        make -C build \
            BL31="${bl31}" \
            ROCKCHIP_TPL="${ddr}" \
            -j$(nproc)
        truncate -s 17M "${out_raw}"
        sfdisk "${out_raw}" <<< "${gpt_mainline}"
        dd if=build/u-boot-rockchip.bin of="${out_raw}" seek=64 conv=notrunc
        ;;
    esac
    gzip -9 --force --suffix '.gz.temp' "${out_raw}" &
    pids_gzip+=($!)
    rm -rf build
}

build_all() {
    outs=()
    pids_gzip=()
    rm -rf build out/list
    mkdir -p out
    local config
    local path_preserve="${PATH}"
    export CROSS_COMPILE=aarch64-linux-gnu-
    export ARCH=arm64
    export PATH="/usr/lib/ccache/bin:${PATH}"
    for config in "${configs_mainline[@]}"; do
        build_common mainline "${uboot_mainline_branch}" "${config}"
    done
    PATH="/usr/lib/ccache/bin:${PWD}/toolchain-vendor/bin:${path_preserve}"
    for config in "${configs_vendor[@]}"; do
        build_common vendor "${uboot_vendor_branch}" "${config}"
    done
    PATH="${path_preserve}"
    rm -rf rkbin
}

finish() {
    wait ${pids_gzip[@]}
    local out
    for out in "${outs[@]}"; do
        if [[ -e "${out}".temp ]]; then
            mv "${out}"{.temp,}
        fi
    done
    local temp_archive=$(mktemp)
    tar -cf "${temp_archive}" "${outs[@]}" out/list
    rm -rf out
    tar -xf "${temp_archive}"
    rm -f "${temp_archive}"

    cd out
    sha256sum * > sha256sums
    cd ..
    cat out/sha256sums >> note.md
    echo '```' >> note.md
}

update_repos
deploy_toolchain_vendor
prepare_rkbin
generate_version
build_all
finish