# ========================
# CORE QUALITY OF LIFE
# ========================
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias c='clear'

# ========================
# PYTHON
# ========================
alias py='python3'
alias pipi='pip3 install'
alias pyrun='python3 main.py'

# ========================
# DOCKER
# ========================
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dlog='docker logs -f'
alias dexec='docker exec -it'

# ========================
# KUBERNETES
# ========================
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kdp='kubectl describe pod'
alias kl='kubectl logs -f'

# ========================
# GIT
# ========================
alias gs='git status'
alias ga='git add .'
alias gc='git commit -m'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# ========================
# QUICK RELOAD
# ========================
alias reload='source ~/.bashrc'

# ========================
# MISC
# ========================
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias epoch='date +%s'

# ========================
# SAFETY
# ========================
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# ========================
# OCI SCCA Landing Zone (vagovoci)
# ========================
alias scca='cd ~/oci-scca-landingzone/Mission_Owner_SCCA_\(SCCAv1\)'
alias tf-init='terraform init'
alias tf-plan='terraform plan -var-file="terraform.tfvars" 2>&1 | tee plan.out'
alias tf-apply='terraform apply -var-file="terraform.tfvars" -auto-approve 2>&1 | tee apply.out'
alias tf-destroy='terraform destroy -var-file="terraform.tfvars" -auto-approve 2>&1 | tee destroy.out'
alias tf-list='terraform state list'
alias tf-count='terraform state list | wc -l'
alias tf-nuke='./pre_destroy.sh && tf-destroy'
alias tf-whoami='grep "resource_label\|tenancy_ocid" ~/oci-scca-landingzone/Mission_Owner_SCCA_\(SCCAv1\)/terraform.tfvars'
alias tf-destroy-status='echo "=== Destroyed ===" && grep "Destruction complete" destroy.out | wc -l && echo "=== Still in state ===" && terraform state list 2>/dev/null | wc -l && echo "=== Last 3 lines ===" && tail -3 destroy.out'
