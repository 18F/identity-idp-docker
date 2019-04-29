# TODO convert this into a multi-stage build?
FROM ubuntu:16.04

# update the date to force a total rebuild
ARG CACHE_BUSTER_DATE=2019-04-26

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get dist-upgrade -y && apt-get install -y cloud-guest-utils awscli

# install chef
COPY docker/scripts/install-chef.sh /tmp/scripts/
RUN /tmp/scripts/install-chef.sh

COPY docker/files/etc-ssh-ssh_known_hosts /etc/ssh/ssh_known_hosts

ARG DEVOPS_BASE_GIT_REF
ARG REPO_DIR=/etc/login.gov/repos

# clone identity-devops
COPY docker/scripts/clone-repo.sh /tmp/scripts/
RUN /tmp/scripts/clone-repo.sh --git-ref "$DEVOPS_BASE_GIT_REF" --auto-s3-ssh-key common/id_ecdsa.identity-servers git@github.com:18F/identity-devops

COPY docker/scripts/run-chef.sh /tmp/scripts/

# Docker doesn't run pam_env.so or source from /etc/environment, so we have to
# set environment variables globally here.
ENV RBENV_ROOT=/opt/ruby_build
ENV PATH='/opt/chef/bin:/opt/ruby_build/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games'
ENV RAILS_ENV=production

# run chef to install idp prereqs
RUN /tmp/scripts/run-chef.sh --kitchen-subdir kitchen --berksfile-toplevel "$REPO_DIR/identity-devops" 'recipe[login_dot_gov::dockerbuild],recipe[passenger::daemon]'

# We need pkgconf and sudo. Lots of other stuff in ubuntu-minimal is not
# strictly needed but comes in handy for debugging.
RUN apt-get install -y sudo pkgconf iputils-ping net-tools netcat-openbsd vim-tiny iproute2 lsb-release

# ====

# check out identity-devops again with main git ref
ARG DEVOPS_GIT_REF
RUN /tmp/scripts/clone-repo.sh --git-ref "$DEVOPS_GIT_REF" --auto-s3-ssh-key common/id_ecdsa.identity-servers git@github.com:18F/identity-devops

# TODO intermediate stuff testing which recipes are needed
RUN /tmp/scripts/run-chef.sh --kitchen-subdir kitchen --berksfile-toplevel "$REPO_DIR/identity-devops" 'recipe[login_dot_gov::users],recipe[identity_base_config],recipe[login_dot_gov::system_users],recipe[sudo]'

# ====

ARG IDP_GIT_REF

# TODO figure out if we can remove this
RUN echo '<dockerbuild>' > /etc/login.gov/info/domain

# TODO fix env-name after secrets management has been improved
RUN /tmp/scripts/run-chef.sh --env-name brody --kitchen-subdir kitchen --berksfile-toplevel --extra-chef-attributes-json "\"login_dot_gov\": {\"branch_name\": \"$IDP_GIT_REF\", \"cloudhsm_enabled\": false}" "$REPO_DIR/identity-devops" 'recipe[login_dot_gov::ssh],recipe[passenger::daemon],recipe[login_dot_gov::idp_base]'

# Clean up files that shouldn't be in final image.
# NB: Don't use this to clear out secrets or keys. Secrets shouldn't ever be
# put in *any* layers since they'll be persisted forever.
RUN rm -fv /etc/login.gov/info/domain /etc/login.gov/info/env

# TODO don't run as root
#USER websrv

# TODO use high ports so we can be non-root
EXPOSE 80 443

# Mount logs on host so we can scoop them up with AWS logs agent on parent host
VOLUME /var/log

COPY docker/scripts/activate-idp.sh /usr/local/bin/activate-idp.sh

CMD /usr/local/bin/activate-idp.sh
