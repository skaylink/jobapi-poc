#!/bin/bash

set -e

codename="${CODENAME}"
component="${COMPONENT:-main}"
reprepro_basedir="reprepro -b ./.repo"
reprepro="${reprepro_basedir} -C ${component}"
gpg --import <<<"${SIGNING_KEY}" 2>&1 | tee /tmp/gpg.log
fingerprint="$(grep -o "key [0-9A-Z]*:" /tmp/gpg.log | grep -o "[0-9A-Z]*" | tail -n1)"
test -f ./.repo/gpg.key || gpg --export --armor "${fingerprint}" >./.repo/gpg.key
sed -i 's,##SIGNING_KEY_ID##,'"${fingerprint}"',' ./.repo/conf/distributions
mapfile -t packages < <(find . -type f -name "*.deb")
for package in "${packages[@]}"; do
    package_name="$(dpkg -f "${package}" Package)"
    package_version="$(dpkg -f "${package}" Version)"
    package_arch="$(dpkg -f "${package}" Architecture)"
    printf "\e[1;36m[%s %s] Checking for package %s %s (%s) in current repo cache ...\e[0m " "${codename}" "${component}" "${package_name}" "${package_version}" "${package_arch}"
    case "${package_arch}" in
    "all")
        filter='Package (=='"${package_name}"'), $Version (=='"${package_version}"')'
        ;;
    *)
        filter='Package (=='"${package_name}"'), $Version (=='"${package_version}"'), $Architecture (=='"${package_arch}"')'
        ;;
    esac
    if [ -d ./.repo/db ]; then
        if $reprepro listfilter "${codename}" "${filter}" | grep -q '.*'; then
            printf "\e[0;32mOK\e[0m\n"
            continue
        fi
    fi
    if grep -q "${package##*/}" <<<"${includedebs[@]}"; then
        printf "\e[0;32mOK\e[0m\n"
        continue
    fi
    printf "\e\033[0;38;5;166mAdding\e[0m\n"
    includedebs+=("${package}")
done
if [ -n "${includedebs}" ]; then
    $reprepro \
        -vvv \
        includedeb \
        "${codename}" \
        "${includedebs[@]}"
fi
if ! $reprepro_basedir -v checkpool fast |& tee /tmp/missing; then
    printf "\e[0;36mStarting repo cache cleanup ...\e[0m\n"
    mapfile -t missingfiles < <(grep "Missing file" /tmp/log | grep --color=never -o "/.*\.deb")
    for missingfile in "${missingfiles[@]}"; do
        missingfile="${missingfile##*/}"
        name="$(cut -d'_' -f 1 <<<"${missingfile}")"
        version="$(cut -d'_' -f 2 <<<"${missingfile}")"
        echo "cleanup missing file ${missingfile} from repo"
        $reprepro \
            -v \
            remove \
            "${codename}" \
            "${name}=${version}"
    done
fi
mkdir -p ./repo
cp -rv ./.repo/gpg.key ./.repo/dists ./.repo/pool ./repo/
