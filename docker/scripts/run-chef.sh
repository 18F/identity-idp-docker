#!/bin/bash
set -euo pipefail

run() {
    echo >&2 "+ $*"
    "$@"
}

# usage: berks_vendor_as_needed
# env vars: $kitchen_subdir, $berksfile_toplevel, $SKIP_BERKS_VENDOR
berks_vendor_as_needed() {
    local vendor_path berks_subdir orig_pwd
    berks_subdir='berks-cookbooks'
    orig_pwd="$PWD"

    if [ -n "${SKIP_BERKS_VENDOR-}" ]; then
        echo >&2 "SKIP_BERKS_VENDOR is set, skipping berks vendor check"
        return
    fi

    echo >&2 "Checking whether vendored berks-cookbooks are up-to-date"
    echo >&2 "Set SKIP_BERKS_VENDOR=1 to skip"

    if [ ! -e "$kitchen_subdir/$berks_subdir" ] || \
       [ -n "$(run find "./$kitchen_subdir/cookbooks" \
                        -newer "$kitchen_subdir/$berks_subdir" \
                        -print -quit
    )" ]; then
        echo >&2 "Found new cookbooks, running berks vendor"
    else
        echo >&2 "$berks_subdir appears up-to-date"
        cd "$orig_pwd"
        return
    fi

    if [ -n "$berksfile_toplevel" ]; then
        echo >&2 "Running berks at toplevel"
        vendor_path="$kitchen_subdir/$berks_subdir"
    else
        echo >&2 "Running berks inside $kitchen_subdir"
        echo >&2 "+ cd '$kitchen_subdir'"
        cd "$kitchen_subdir"
        vendor_path="$berks_subdir"
    fi

    run berks vendor "$vendor_path"

    run touch "$vendor_path"
    cd "$orig_pwd"
}

usage() {
    cat >&2 <<EOM
usage: $0 [options] REPO_DIR RUN_LIST

Arguments:
    REPO_DIR: The directory containing the chef repository
    RUN_LIST: The chef run list (passed to chef-client -o)

Options:
    --kitchen-subdir DIR        The subdirectory to cd to for running chef
    --env-name ENV              The environment name to use
    --berksfile-toplevel        Use if Berksfile is outside the kitchen subdir
    --extra-chef-attributes-json JSON
                                Pass in raw JSON keypairs to set any desired
                                chef attributes. This will be interpolated
                                inside enclosing braces '{}', so a valid
                                argument might look like:
                                '"foo": true, "bar": {"sub": "thing"}'

EOM
}

env_name='dockerbuild'
extra_chef_attributes_json='"no_op_default": true'
kitchen_subdir='chef'

while [ $# -gt 0 ] && [[ $1 = -* ]]; do
    case "$1" in
        --env-name)
            env_name="$2"
            shift
            ;;
        --kitchen-subdir)
            kitchen_subdir="$2"
            shift
            ;;
        --berksfile-toplevel)
            berksfile_toplevel=1
            ;;
        --extra-chef-attributes-json)
            extra_chef_attributes_json="$2"
            shift
            ;;
        *)
            usage
            echo >&2 "Unexpected option $1"
            exit 1
            ;;
    esac
    shift
done

if [ $# -ne 2 ]; then
    usage
    exit 1
fi

REPO_DIR="$1"
RUN_LIST="$2"

INFO_DIR=/etc/login.gov/info

mkdir -p "$INFO_DIR"
run tee >&2 "$INFO_DIR/env" <<< "$env_name"

# default EC2 instance "run_list": ["role[idp]"], right now we specify an empty
# run list for docker
run tee >&2 "$INFO_DIR/chef-attributes.json" <<EOM
{
    "run_list": [],
    "provisioner": {
        "name": "docker",
        "auto-scaled": true,
        "role": "idp"
    },
    $extra_chef_attributes_json
}
EOM

echo >&2 "+ cd '$REPO_DIR'"
cd "$REPO_DIR"


echo >&2 "==========================================================="
echo >&2 "$0: running berks to vendor cookbooks"
berks_vendor_as_needed

echo >&2 "==========================================================="
echo >&2 "$0: Starting chef run!"
echo >&2 "+ cd '$kitchen_subdir'"
cd "$kitchen_subdir"

run pwd

# We expect there to be a chef-client.rb in the `chef` directory of the repo
# that tells us where to find cookbooks and also sets the environment and run
# list. (The run list probably needs to be set via a json_attribs file put in
# place by cloud-init or other provisioner).

# Chef doesn't error out if config not found, so we check ourselves
if ! [ -e "./chef-client.rb" ]; then
    echo >&2 "Error: no chef-client.rb found in $PWD"
    exit 3
fi

run chef-client --local-mode -c "./chef-client.rb" --no-color -o "$RUN_LIST"

run rm -rf /tmp/bundler

echo >&2 "All done with $0!"
