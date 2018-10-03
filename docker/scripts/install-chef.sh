#!/bin/bash
# shellcheck disable=SC2230
set -euo pipefail

CHEF_URL=https://packages.chef.io/files/stable/chef/13.11.3/ubuntu/16.04/chef_13.11.3-1_amd64.deb
CHEF_SHA256=1517823c278b34ea42d7624603f9507d54b49b511ebfc34ca6c4033cf8d46d6d

run() {
    echo >&2 "+ $*"
    "$@"
}

# usage: install_chef URL CHECKSUM
install_chef() {
    local tmpdir installer url expected_checksum checksum
    echo >&2 "Downloading chef"

    url="$1"
    expected_checksum="$2"

    tmpdir="$(run mktemp -d)"

    installer="$tmpdir/chef.deb"

    run wget -nv -O "$installer" "$url"

	checksum="$(run sha256sum "$installer" | cut -d' ' -f1)"
	if [ "$checksum" != "$expected_checksum" ]; then
		echo >&2 "Download checksum mismatch in $installer:"
		echo >&2 "Expected: $expected_checksum"
		echo >&2 "Got:      $checksum"
		return 2
	fi

    echo >&2 "Installing chef"
    run dpkg -i "$installer"

    echo >&2 "Successfully installed"

    run rm -r "$tmpdir"
}


# Duplicated from provision.sh (TODO)
#
# Check whether berkshelf is already installed. If not, install berkshelf by
# using gem install to get a version appropriate for the chef embedded ruby
# version. This may be an old version of berkshelf.
check_install_berkshelf() {
    local embedded_bin chef_version berks_version

    echo >&2 "Checking for installed berkshelf"

    if which berks >/dev/null; then
        echo >&2 "berks found on path"
        return
    fi

    embedded_bin="/opt/chef/embedded/bin"

    if [ ! -d "$embedded_bin" ]; then
        echo >&2 "Error: could not find chef embedded bin at $embedded_bin"
        return 1
    fi

    if [ -e "$embedded_bin/berks" ]; then
        echo >&2 "Berks found at $embedded_bin/berks"
        return
    fi

    echo >&2 "Installing berkshelf"

    run "$embedded_bin/chef-client" --version
    run "$embedded_bin/ruby" --version

    chef_version="$(run "$embedded_bin/chef-client" --version)"

    case "$chef_version" in
        'Chef: 13.'*)
            run "$embedded_bin/gem" install -v '~> 6.0' --no-ri --no-rdoc berkshelf
            ;;
        *)
            echo >&2 "Error: Unknown chef version $chef_version"
            exit 3
            ;;
    esac

    echo >&2 "Checking installed berkshelf"

    berks_version="$(run "$embedded_bin/berks" --version)"

    # belt + suspenders
    if [ -z "$berks_version" ]; then
        echo >&2 "Something went wrong"
        return 2
    fi

    # symlink into PATH as needed
    if ! which berks >/dev/null; then
        run ln -sfv "$embedded_bin/berks" "/usr/local/bin/berks"
    fi

    echo >&2 "Berkshelf version $berks_version is good to go!"
}

run apt-get update

run apt-get install -y wget git build-essential

install_chef "$CHEF_URL" "$CHEF_SHA256"

check_install_berkshelf


