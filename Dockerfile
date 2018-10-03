# TODO convert this into a multi-stage build
FROM ubuntu:16.04
ARG IDP_GIT_REF=
ARG DEVOPS_GIT_REF=

RUN apt-get update && apt-get dist-upgrade -y

# install chef
COPY docker/scripts/install-chef.sh /tmp/scripts/
RUN /tmp/scripts/install-chef.sh

# clone identity-devops
COPY docker/scripts/clone-repo.sh /tmp/scripts/
RUN /tmp/scripts/clone-repo.sh --git-ref "$DEVOPS_GIT_REF" --auto-s3-ssh-key common/id_ecdsa.identity-devops.deploy git@github.com:18F/identity-devops

# run chef and install idp
COPY docker/scripts/install-idp.sh /tmp/scripts/
RUN /tmp/scripts/install-idp.sh "$IDP_GIT_REF"

CMD echo "Hello, this is a test"
