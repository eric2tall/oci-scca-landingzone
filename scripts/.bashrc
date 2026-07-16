# .bashrc
# Source global definitions
if [ -f /etc/bashrc ]; then
        . /etc/bashrc
fi
# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH
# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=
# User specific aliases and functions
source /etc/bashrc.cloudshell
# vi mode for command line editing
set -o vi
# Load custom aliases
source ~/aliases.sh
# Git-aware prompt
git_repo_branch() {
  local branch repo
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || branch=$(git rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
    echo " ($repo:$branch)"
  fi
}
export PS1='\[\033[01;34m\]\u@\h:\w\[\033[00m\]\[\033[01;33m\]$(git_repo_branch)\[\033[00m\]\$ '
