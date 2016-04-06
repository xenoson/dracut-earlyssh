

info "Stopping dropbear sshd: dracut-dropbear.service"
systemctl stop dracut-dropbear.service --job-mode=ignore-dependencies
[ $? -gt 0 ] && info 'Dropbear sshd failed to stop'