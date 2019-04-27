# TODO convert this into a multi-stage build
FROM ubuntu:16.04

# update the date to force a total rebuild
ARG CACHE_BUSTER_DATE=2019-04-26

RUN apt-get update && apt-get dist-upgrade -y && apt-get install -y cloud-guest-utils awscli

# install chef
COPY docker/scripts/install-chef.sh /tmp/scripts/
RUN /tmp/scripts/install-chef.sh

COPY docker/files/etc-ssh-ssh_known_hosts /etc/ssh/ssh_known_hosts

ARG DEVOPS_GIT_REF
ARG REPO_DIR=/etc/login.gov/repos

# clone identity-devops
COPY docker/scripts/clone-repo.sh /tmp/scripts/
RUN /tmp/scripts/clone-repo.sh --git-ref "$DEVOPS_GIT_REF" --auto-s3-ssh-key common/id_ecdsa.identity-servers git@github.com:18F/identity-devops

COPY docker/scripts/run-chef.sh /tmp/scripts/

# run chef to install idp prereqs
RUN /tmp/scripts/run-chef.sh --kitchen-subdir kitchen --berksfile-toplevel "$REPO_DIR/identity-devops" 'recipe[login_dot_gov::dockerbuild],recipe[passenger::daemon]'

ARG IDP_GIT_REF

# run chef and install idp
COPY docker/scripts/install-idp.sh /tmp/scripts/
#RUN /tmp/scripts/install-idp.sh "$IDP_GIT_REF"
RUN ["/tmp/scripts/run-chef.sh", "--kitchen-subdir", "kitchen", "--berksfile-toplevel", "--extra-chef-attributes-json", "\"login_dot_gov\": {\"branch_name\": \"$IDP_GIT_REF\"}", "$REPO_DIR/identity-devops", "recipe[login_dot_gov::idp_base]"]

CMD echo "Hello, this is a test"
