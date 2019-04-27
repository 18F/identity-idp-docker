#!/bin/bash
set -euo pipefail

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

run() {
    echo >&2 "+ $*"
    "$@"
}

env_name='dockerbuild'
extra_chef_attributes_json='"no_op_default": true'
kitchen_subdir='chef'
berks_subdir='berks-cookbooks'

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
run tee "$INFO_DIR/env" <<< "$env_name"

# default EC2 instance "run_list": ["role[idp]"], right now we specify an empty
# run list for docker
run tee "$INFO_DIR/chef-attributes.json" <<EOM
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


echo "==========================================================="
echo "$0: running berks to vendor cookbooks"

# If Berksfile is at repo toplevel, run outside the kitchen_subdir
if [ -n "$berksfile_toplevel" ]; then
    echo >&2 "Running berks at toplevel"
    run berks vendor "$kitchen_subdir/$berks_subdir"
fi

echo >&2 "+ cd '$kitchen_subdir'"
cd "$kitchen_subdir"

# If Berksfile is not at repo toplevel, run inside the kitchen_subdir
if [ -z "$berksfile_toplevel" ]; then
    echo >&2 "Running berks"
    run berks vendor "$berks_subdir"
fi

echo "==========================================================="
echo "$0: Starting chef run!"

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
