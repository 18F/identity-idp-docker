#!/bin/bash
set -euo pipefail

run() {
    echo >&2 "+ $*"
    "$@"
}

# Run chef to finalize configuration
run id-chef-client main -o 'recipe[instance_certificate::generate],recipe[service_discovery::register],recipe[login_dot_gov::idp_web]'

# Exec and start up nginx
run exec /opt/nginx/bin/nginx -g 'daemon off;'
