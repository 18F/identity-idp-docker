#!/bin/bash
set -euo pipefail

run() {
    echo >&2 "+ $*"
    "$@"
}

BASENAME="$(basename "$0")"
log() {
    echo >&2 "$BASENAME: $*"
}

# usage: ok_to_reuse_target TARGET_DIR EXPECTED_ORIGIN
# env_vars: $CHECKOUT_REUSE_OK
ok_to_reuse_target() {
    local target_dir expected_origin origin_url
    target_dir="$1"
    expected_origin="$2"

    if [ -z "$CHECKOUT_REUSE_OK" ]; then
        echo >&2 "Error: cannot reuse existing checkout due to --fail-existing"
        return 1
    fi

    (
    cd "$target_dir"
    # Double check that the origin remote matches our expected REPO_URL before
    # reusing an existing checkout.
    origin_url="$(run git remote get-url origin || true)"

    if [ "$origin_url" != "$expected_origin" ]; then
        echo >&2 "Error: existing checkout origin remote differs from expected"
        echo >&2 "Expected origin: $expected_origin"
        echo >&2 "Actual origin:   $origin_url"
        return 3
    fi
    )
}


REPO_DIR=/etc/login.gov/repos
SSH_AUTO_BUCKET_PREFIX=login-gov.secrets

usage() {
    cat >&2 <<EOM
usage: $(basename "$0") [OPTIONS] REPO_URL [REPO_DIR]

Git clone REPO_URL under REPO_DIR.

REPO_DIR: defaults to "$REPO_DIR"

Options:
    --s3-ssh-key-url S3_URL       An S3 URL used to download the SSH key that
                                  can be used to clone REPO_URL.
    --auto-s3-ssh-key KEY_PATH    Like --s3-ssh-key-url, but but automatically
                                  determine the bucket of the form
                                  $SSH_AUTO_BUCKET_PREFIX.<account-id>-<region>.
                                  KEY_PATH is the path to the SSH key within
                                  this bucket.
    --fail-existing               By default, reuse an existing checkout. Set
                                  this flag to error out instead.
    --git-ref REF                 Check out GIT_REF after cloning the repo.

EOM
}

get_aws_account_id() {
    run aws sts get-caller-identity --output text --query Account
}
get_aws_region() {
    local az
    az="$(run ec2metadata --availability-zone)"
    echo "${az::-1}"
}

s3_ssh_key_url=
auto_s3_ssh_key_basename=
git_ref=
CHECKOUT_REUSE_OK=1

while [ $# -gt 0 ] && [[ $1 == -* ]]; do
    case "$1" in
        --s3-ssh-key-url)
            s3_ssh_key_url="$2"
            shift
            ;;
        --auto-s3-ssh-key)
            auto_s3_ssh_key_basename="$2"
            shift
            ;;
        --git-ref)
            git_ref="$2"
            shift
            ;;
        --fail-existing)
            CHECKOUT_REUSE_OK=
            ;;
        -h|--help)
            usage
            exit
            ;;
        *)
            usage
            exit 1
            ;;
    esac
    shift
done

case $# in
    1)
        REPO_URL="$1"
        ;;
    2)
        REPO_URL="$1"
        REPO_DIR="$2"
        ;;
    *)
        usage
        exit 1
        ;;
esac

if [ -n "$auto_s3_ssh_key_basename" ]; then
    if [ -n "$s3_ssh_key_url" ]; then
        usage
        echo >&2 "Error: can't specify auto S3 URL and explicit S3 URL"
        exit 2
    fi

    bucket="$SSH_AUTO_BUCKET_PREFIX.$(get_aws_account_id)-$(get_aws_region)"
    s3_ssh_key_url="s3://$bucket/$auto_s3_ssh_key_basename"
fi

log "checking out $REPO_URL to $REPO_DIR"

mkdir -vp "$REPO_DIR"

cd "$REPO_DIR"

if [ -n "$s3_ssh_key_url" ]; then
    echo >&2 "Downloading SSH key from S3 at $s3_ssh_key_url"

    secrets_dir="$(run mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$secrets_dir'" EXIT

    run aws s3 cp --sse aws:kms "$s3_ssh_key_url" "$secrets_dir/"
    run aws s3 cp --sse aws:kms "$s3_ssh_key_url.pub" "$secrets_dir/"

    ssh_key_path="$secrets_dir/$(basename "$s3_ssh_key_url")"
    run chmod -c 600 "$ssh_key_path"

    echo >&2 "+ export GIT_SSH_COMMAND=\"ssh -i '$ssh_key_path'\""
    export GIT_SSH_COMMAND="ssh -i '$ssh_key_path'"
fi

target="$(basename "$REPO_URL")"

if [ -d "$target" ] && ok_to_reuse_target "$target" "$REPO_URL" ; then
    echo >&2 "Reusing existing checkout: $target"
    (
        cd "$target"
        run git fetch
    )
else
    run git clone "$REPO_URL"
fi

# check out specified git ref as desired
if [ -n "$git_ref" ]; then
    cd "$target"
    run git checkout "$git_ref"
fi

log "finished"
