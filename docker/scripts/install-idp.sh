#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo >&2 "usage: $0 IDP_GIT_REF"
    exit 1
fi

run() {
    echo >&2 "+ $*"
    "$@"
}

IDP_GIT_REF="$1"

INFO_DIR=/etc/login.gov/info
kitchen_subdir=kitchen
berks_subdir=berks-cookbooks

run apt-get update -y
DEBIAN_FRONTEND=noninteractive run apt-get \
    -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    dist-upgrade -y

mkdir -p "$INFO_DIR"
echo 'dockerbuild' > "$INFO_DIR/env"

# default EC2 instance "run_list": ["role[idp]"], right now we specify an empty
# run list for docker
cat > "$INFO_DIR/chef-attributes.json" <<EOM
{
    "run_list": ["recipe[passenger::daemon]", "recipe[login_dot_gov::idp_base]"],
    "provisioner": {
        "name": "docker",
        "auto-scaled": true,
        "role": "idp"
    },
    "login_dot_gov": {
        "branch_name": "$IDP_GIT_REF"
    }
}
EOM

cd /etc/login.gov/repos/identity-devops


echo "==========================================================="
echo "$0: running berks to vendor cookbooks"

echo >&2 "Running berks at toplevel"
run berks vendor "$kitchen_subdir/$berks_subdir"

echo "cd '$kitchen_subdir'"
cd "$kitchen_subdir"

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

run chef-client --local-mode -c "./chef-client.rb" --no-color

run rm -rf /tmp/bundler

echo >&2 "All done with $0!"
