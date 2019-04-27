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

# TODO move this to top
# TODO: figure out if we should be doing something to cause docker to source pam_env.so / run pam to read /etc/environment
ENV RBENV_ROOT=/opt/ruby_build

# TODO intermediate stuff testing which recipes are needed
RUN /tmp/scripts/run-chef.sh --kitchen-subdir kitchen --berksfile-toplevel "$REPO_DIR/identity-devops" 'recipe[login_dot_gov::users],recipe[identity_base_config],recipe[login_dot_gov::system_users]'
# TODO figure out why sudo isn't installed / where it should be coming from
RUN apt-get install -y sudo
RUN /tmp/scripts/run-chef.sh --kitchen-subdir kitchen --berksfile-toplevel "$REPO_DIR/identity-devops" 'recipe[sudo]'

# TODO move this into a recipe or something
RUN apt-get install -y pkgconf

# run chef and install idp
#COPY docker/scripts/install-idp.sh /tmp/scripts/
#RUN /tmp/scripts/install-idp.sh "$IDP_GIT_REF"

ARG IDP_GIT_REF

# TODO move this to top with RBENV_ROOT
ENV PATH='/opt/chef/bin:/opt/ruby_build/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games'
ENV RAILS_ENV=production

# TODO figure out if we can remove this
RUN echo '<dockerbuild>' > /etc/login.gov/info/domain

# TODO fix env-name after secrets management has been improved
RUN /tmp/scripts/run-chef.sh --env-name brody --kitchen-subdir kitchen --berksfile-toplevel --extra-chef-attributes-json "\"login_dot_gov\": {\"branch_name\": \"$IDP_GIT_REF\", \"cloudhsm_enabled\": false}" "$REPO_DIR/identity-devops" 'recipe[login_dot_gov::ssh],recipe[passenger::daemon],recipe[login_dot_gov::idp_base]'

CMD echo "Hello, this is a test"
