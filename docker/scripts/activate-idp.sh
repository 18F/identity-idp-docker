#!/bin/bash
set -euo pipefail

run() {
    echo >&2 "+ $*"
    "$@"
}

if [ -n "${DEVOPS_ACTIVATE_GIT_REF-}" ]; then
    cd /etc/login.gov/repos/identity-devops
    run git fetch
    run git checkout "$DEVOPS_ACTIVATE_GIT_REF"
fi

# Run chef to finalize configuration
# TODO figure out how to remove recipe[passenger::daemon], by making idp_web
# not depend on service[passenger]
run id-chef-client main -o 'recipe[passenger::daemon],recipe[instance_certificate::generate],recipe[service_discovery::register],recipe[login_dot_gov::idp_web]'

run service passenger stop

# Exec and start up nginx
run exec /opt/nginx/sbin/nginx -g 'daemon off;'
