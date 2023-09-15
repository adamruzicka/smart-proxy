# # Base container that is used for both building and running the app
# FROM quay.io/centos/centos:stream8 as base

# RUN dnf install -y https://yum.theforeman.org/releases/nightly/el8/x86_64/foreman-release.rpm && \
# 	dnf module enable -y foreman:el8 && \
#     dnf install -y foreman-proxy && \
# 	dnf clean all

# RUN echo ':http_port: 8000' >> /etc/foreman-proxy/settings.yml && \
#     echo ':log_file: STDOUT' >> /etc/foreman-proxy/settings.yml

# RUN dnf install -y rubygem-smart_proxy_remote_execution_ssh && \
#     dnf clean all

# EXPOSE 8000

# CMD ["/usr/share/foreman-proxy/bin/smart-proxy"]

# Base container that is used for both building and running the app
FROM quay.io/centos/centos:stream8 as base
ARG RUBY_VERSION="3.1"

RUN \
  dnf upgrade -y && \
  dnf module enable ruby:${RUBY_VERSION} -y && \
  dnf install -y postgresql-libs ruby{,gems} rubygem-{rake,bundler} nc hostname openssh-clients && \
  dnf clean all

ARG HOME=/home/foreman
WORKDIR $HOME
RUN groupadd -r foreman -f -g 0 && \
    useradd -u 1001 -r -g foreman -d $HOME -s /sbin/nologin \
    -c "Foreman Application User" foreman && \
    chown -R 1001:0 $HOME && \
    chmod -R g=u ${HOME}

# Temp container that download gems/npms and compile assets etc
FROM base as builder
ENV BUNDLER_SKIPPED_GROUPS="bmc dhcp_isc journald krb5 libvirt realm_freeipa windows puppet_proxy_legacy"

RUN \
  dnf install -y --enablerepo=powertools redhat-rpm-config git-core \
    gcc-c++ make bzip2 gettext tar \
    libxml2-devel libcurl-devel ruby-devel libyaml-devel \
    postgresql-devel && \
  dnf clean all
ARG HOME=/home/foreman
USER 1001
WORKDIR $HOME
COPY --chown=1001:0 . ${HOME}/
RUN bundle config set --local without "${BUNDLER_SKIPPED_GROUPS}" && \
  bundle config set --local clean true && \
  bundle config set --local path vendor && \
  bundle config set --local jobs 5 && \
  bundle config set --local retry 3
RUN bundle install && \
  bundle binstubs --all && \
  rm -rf vendor/ruby/*/cache && \
  find vendor/ruby/*/gems -name "*.c" -delete && \
  find vendor/ruby/*/gems -name "*.o" -delete

USER 0
RUN chgrp -R 0 ${HOME} && \
    chmod -R g=u ${HOME}

USER 1001

FROM base

ARG HOME=/home/foreman

USER 1001
WORKDIR ${HOME}
COPY --chown=1001:0 . ${HOME}/
# COPY --from=builder /usr/bin/entrypoint.sh /usr/bin/entrypoint.sh
COPY --from=builder --chown=1001:0 ${HOME}/.bundle/config ${HOME}/.bundle/config
COPY --from=builder --chown=1001:0 ${HOME}/Gemfile.lock ${HOME}/Gemfile.lock
COPY --from=builder --chown=1001:0 ${HOME}/vendor/ruby ${HOME}/vendor/ruby

RUN date -u > BUILD_TIME

RUN cp config/settings.yml.example config/settings.yml && \
    echo ':http_port: 8000' >>  config/settings.yml && \
    echo ':log_file: STDOUT' >> config/settings.yml

# Start the main process.
CMD bundle exec ruby bin/smart-proxy

EXPOSE 8000/tcp
