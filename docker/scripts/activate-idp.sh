#!/bin/bash
set -euo pipefail

run() {
    echo >&2 "+ $*"
    "$@"
}

# Run chef to finalize configuration
# TODO figure out how to remove recipe[passenger::daemon], by making idp_web
# not depend on service[passenger]
run id-chef-client main -o 'recipe[passenger::daemon],recipe[instance_certificate::generate],recipe[service_discovery::register],recipe[login_dot_gov::idp_web]'

# Exec and start up nginx
run exec /opt/nginx/bin/nginx -g 'daemon off;'
