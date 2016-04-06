

info "start-dropbear was called with parameter: $@"
#above could be helpful to bind to one specific interface
#with ip kernel parameter we can set the interface name
#rd.neednet=1 ip=192.168.1.110::192.168.1.254:255.255.255.0:localhost:enp0s3:none 
#this script gets called with parameter enp0s3 then


info "Starting dropbear sshd"
systemctl start dracut-dropbear.service --job-mode=ignore-dependencies
[ $? -gt 0 ] && info 'Dropbear sshd failed to start'

#debug
#emergency_shell -n start-dropbear "Break from 50-start-dropbear.sh in initqueue/online"
#info "continue 50-start-dropbear.sh"
