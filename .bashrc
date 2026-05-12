# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
if ! [[ "$PATH" =~ "$HOME/.npm-global/bin" ]]; then
    PATH="$PATH:$HOME/.npm-global/bin"
fi
export PATH

if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b)"
fi

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi

ai() {
    if [ "$#" -eq 0 ]; then
        printf 'Usage: ai <prompt>\n' >&2
        return 1
    fi
    sgpt "$*"
}

unset rc
