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
if [[ -d "$HOME/go/bin" ]] && ! [[ "$PATH" =~ "$HOME/go/bin" ]]; then
    PATH="$PATH:$HOME/go/bin"
fi
export PATH

if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b)"
fi

if [[ $- == *i* ]]; then
    __dotfiles_strip_prompt_color() {
        local raw="$1"
        local prefix suffix code

        for code in 31 32 35 36; do
            prefix="\\[\\e[0;${code}m\\]"
            suffix="\\[\\e[0m\\]"
            if [[ "$raw" == "$prefix"*"$suffix" ]]; then
                raw="${raw#"$prefix"}"
                raw="${raw%"$suffix"}"
                break
            fi
        done

        printf '%s' "$raw"
    }

    if [[ -n "${DISTROBOX_ENTER_PATH:-}" ]]; then
        if [[ "${CONTAINER_ID:-}" == "damianu" || "${CONTAINER_ID:-}" == "ubuntu-dev" ]]; then
            PS1='\[\e[0;36m\]📦[\u@distrobx damianu]\$ \[\e[0m\]'
        elif [[ "${CONTAINER_ID:-}" == "security" ]]; then
            PS1='\[\e[0;31m\]📦[\u@distrobx security]\$ \[\e[0m\]'
        elif [[ "${CONTAINER_ID:-}" == "damianf" || "${CONTAINER_ID:-}" == "damian" ]]; then
            PS1='\[\e[0;31m\]📦[\u@distrobx damianf]\$ \[\e[0m\]'
        else
            PS1='\[\e[0;31m\]📦[\u@'"${CONTAINER_ID:-container}"' \W]\$ \[\e[0m\]'
        fi
    elif [[ -n "${TOOLBOX_PATH:-}" ]]; then
        PS1='\[\e[0;36m\]⬢ [\u@toolbx damianf]\$ \[\e[0m\]'
    elif [[ -f /run/.containerenv ]]; then
        PS1='\[\e[0;31m\]'"$(__dotfiles_strip_prompt_color "$PS1")"'\[\e[0m\]'
    else
        PS1='\[\e[0;32m\]'"$(__dotfiles_strip_prompt_color "$PS1")"'\[\e[0m\]'
    fi

    unset -f __dotfiles_strip_prompt_color
fi

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

if [[ $- == *i* ]]; then
    # fzf uses Ctrl-R, Ctrl-T, and Alt-C. This repo does not bind those keys elsewhere.
    for fzf_key_bindings in \
        /usr/share/fzf/shell/key-bindings.bash \
        /usr/share/doc/fzf/examples/key-bindings.bash; do
        if [[ -r "$fzf_key_bindings" ]]; then
            # shellcheck source=/dev/null
            source "$fzf_key_bindings"
            break
        fi
    done

    for fzf_completion in \
        /usr/share/fzf/shell/completion.bash \
        /usr/share/doc/fzf/examples/completion.bash; do
        if [[ -r "$fzf_completion" ]]; then
            # shellcheck source=/dev/null
            source "$fzf_completion"
            break
        fi
    done

    unset fzf_key_bindings fzf_completion
fi

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

damianf() {
    command damianf "$@"
}

damianu() {
    command damianu "$@"
}

unset rc
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
