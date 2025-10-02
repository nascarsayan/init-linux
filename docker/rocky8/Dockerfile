FROM rockylinux:8

RUN dnf update -y \
    && dnf install -y \
       curl \
       tar \
       gzip \
       git \
       zsh \
       which \
    && dnf clean all

COPY scripts/sayann-install.sh /usr/local/src/sayann-install.sh
COPY templates/zshrc-tpl.zsh /usr/local/templates/zshrc-tpl.zsh
COPY templates/tmuxrc-tpl.conf /usr/local/templates/tmuxrc-tpl.conf
COPY docker/rocky8/entrypoint.sh /usr/local/bin/sayann-entrypoint
RUN chmod +x /usr/local/src/sayann-install.sh /usr/local/bin/sayann-entrypoint

ENTRYPOINT ["/usr/local/bin/sayann-entrypoint"]
