FROM rockylinux:8

RUN dnf update -y \
    && dnf install -y \
       curl \
       tar \
       gzip \
       git \
       zsh \
       tmux \
       which \
       findutils \
    && dnf clean all

COPY scripts/sandbox-install.sh /usr/local/src/sandbox-install.sh
COPY templates/zshrc-tpl.zsh /usr/local/templates/zshrc-tpl.zsh
COPY templates/tmuxrc-tpl.conf /usr/local/templates/tmuxrc-tpl.conf
COPY templates/p10k.zsh /usr/local/templates/p10k.zsh
COPY docker/rocky8/entrypoint.sh /usr/local/bin/sandbox-entrypoint
RUN chmod +x /usr/local/src/sandbox-install.sh /usr/local/bin/sandbox-entrypoint

ENTRYPOINT ["/usr/local/bin/sandbox-entrypoint"]
