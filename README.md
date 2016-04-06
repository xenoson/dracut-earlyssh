dracut-earlyssh
---------------

[Dracut initramfs](https://dracut.wiki.kernel.org/index.php/Main_Page) module
to start [Dropbear sshd](https://matt.ucc.asn.au/dropbear/dropbear.html)
on early boot to enter encryption passphrase remotely or just
connect and debug.

There are a number of reasons why you would want to do this:
 1. It provides a way of entering the encryption keys for a number of servers without
    console switching
 2. It allows remote booting of (externally-hosted) encrypted servers

This is based heavily on the work of others, in particular mk-fg.  The major changes between
this version are: adaption for RHEL 6 and the old version of dracut installed there;
additional options for replicated the system host key or a user provided one (see the
"dropbear_rsa_key" option, documented in earlyssh.conf); an additional utility (unlock)
for automating the unlock process.  

Users are strictly authenticated by provided SSH public keys. These can be either:
root's ~/.ssh/authorized_keys or a custom file ("dropbear_acl" option).  Depending
on your environment, it may make sense to make the preboot authorized_keys file
quite different to the normal one.

See dropbear(8) manpage for full list of supported restrictions there (which are
fairly similar to openssh).  If using in combination with the unlock utility (see below), a useful restriction may be to make /bin/unlock a 'forced command' in SSH.


### Usage

First of all, you must have dropbear. CentOS/RHEL users can get this from EPEL.  

- Check out supported dracut.conf options below.
  With no extra options, ad-hoc server rsa key will be generated (and its
  fingerprint/bbcode will be printed to dracut log),
  `/root/.ssh/authorized_keys` will be used for ACL.

- See dracut.cmdline(7) manpage for info on how to setup "network" module
  (otherwise sshd is kinda useless).

  Simplest way might be just passing `ip=dhcp rd.neednet=1` on cmdline, if dhcp
  can assign predictable ip and pass proper routes.

  On older Dracut versions (e.g. 004 in RHEL6), networking is only configured
  if you have configured a network root.  In order to work around this, dracut-earlyssh
  system will install a dummyroot script (if it detects dracut v004 at build-time).
  The cmdline for these versions should be `ip=dhcp netroot=dummy`. 

- Put 60dropbear in to dracut modules directory, usually /lib/dracut/modules.d

- Run dracut to build initramfs with the thing.

- Probably you need to build the initramfs from the installer.
  See 
  https://bugzilla.redhat.com/show_bug.cgi?id=524727#c23
  in how to boot the installer via grub to allow ssh logins.
  chmod into encrypted system before rebuilding with 
  dracut --kver kernelverinboot --force

On boot, sshd will be started with:

- Port: ${dropbear_port} (dracut.conf) or 2222 (default).

- User (to allow login as-): root

- Host key: ${dropbear_rsa_key} (dracut.conf) or generated
  (fingerprint echoed during generation and to console on sshd start).
  DSA keys are not supported (and shouldn't generally be used with ssh).

- Client key(s): ${dropbear_acl} (dracut.conf) or `/root/.ssh/authorized_keys`

- Password auth and port forwarding explicitly disabled.

Dropbear should echo a few info messages on start (unless rd.quiet or similar
options are used) and print host ssh key fingerprint to console, as well as any
logging (e.g. errors, if any) messages.

Do check the fingerprints either by writing them down on key generation, console
or through network perspectives at least.


To login:

    % ssh -p2222 root@some.remote.host.tld

Shell is /bin/sh, which should be
[dash](http://gondor.apana.org.au/~herbert/dash/) in most dracut builds, but can
probably be replaced with ash (busybox) or bash (heavy) using appropriate modules.


After the system starts booting, sshd should be killed during dracut "cleanup" phase, once 
main os init is about to run.

### Remote unlock using the 'unlock' script
  It essentially just calls /usr/bin/systemd-tty-ask-password-agent --query
  But therer is a severe Bug to consider:
  xxxx

### dracut.conf parameters

- dropbear_port

- dropbear_rsa_key

- dropbear_acl

See above.


### Common issues and non-issues

- `Dropbear sshd failed to start`

Only means what it says, see output of dropbear *before* it died - it should
print some specific errors which led to it exiting like that.

- `Failed reading '-', disabling DSS`

Will *always* be printed and should be ignored - DSA keys are not generated/used
in these scripts, and probably shouldn't be.

- Host hangs in initramfs, but can't be pinged (e.g. `ping my.host.tld`) from outside.

Either no network configuration parameters were passed to dracut, or it failed
to configure at least one IP address.

Don't forget `rd.neednet=1` on cmdline, as dracut will ignore specified network
settings without nfs (or whatever net-) root otherwise.

Read up dracut.cmdline(7), "Network" section and/or see why/if dracut failed to
configure net as requested with `rd.debug`.
See also "Debugging tips" section below.

- Host pings, but ssh can't connect.

Try `nc -v <host> <port>`, or "ncat" instead of "nc" there.
"ncat" can be found in "nmap" package, "nc" usually comes pre-installed.

If it hangs without printing "Connected to ..." line - can be some firewall
before host or dropbear failed to start/listen.

If there's no "SSH-2.0-dropbear_..." after "Connected to ..." line - some issue
with dropbear.

- `lastlog_perform_login: Couldn't stat /var/log/lastlog: No such file or directory`

Pops up when logging in, can be safely ignored.


### Debugging tips

If (or rather "when") something goes wrong and you can't access just-booted
machine over network and can't get to console (hence sshd in initramfs), don't
panic - it's fixable if machine can be rebooted into some rescue system
remotely.

Usually it's some dhcp+tftp netboot thing from co-located machine (good idea to
setup/test in advance) plus whoever is there occasionally pushing the power
button, or maybe some fancy hw/interface for that (e.g. hetzner "rescue" interface).

To see what was going on during initramfs, open
"modules.d/99base/rdsosreport.sh" in dracut, append this (to the end):

	set -x
	netstat -lnp
	netstat -np
	netstat -s
	netstat -i
	ip addr
	ip ro
	set +x

	exec >/dev/null 2>&1
	mkdir /tmp/myboot
	mount /dev/sda2 /tmp/myboot
	cp /run/initramfs/rdsosreport.txt /tmp/myboot/
	umount /tmp/myboot
	rmdir /tmp/myboot

Be sure to replace `/dev/sda2` with whatever device is used for /boot, rebuild
dracut and add `rd.debug` to cmdline (e.g. in grub.cfg's "linux" line).

Upon next reboot, *wait* for at least a minute, since dracut should give up on
trying to boot the system first, then it will store full log of all the stuff
modules run ("set -x") and their output in "/boot/rdsosreport.txt".

Naturally, to access that, +1 reboot into some "rescue" system might be needed.

In case of network-related issues - e.g. if "rdsosreport.txt" file gets created
with "rd.debug", but host can't be pinged/connected-to for whatever reason -
either enable "debug" dracut module or add `dracut_install netstat ip` line to
`install()` section of "modules.d/60dropbear-sshd/module-setup.sh" and check
"rdsosreport.txt" or console output for whatever netstat + ip commands above
(for "rdsosreport.sh") show - there can be no default route, whatever interface
naming mixup, no traffic (e.g. unrelated connection issue), etc.


### TODO



### Based on code, examples and ideas from

- https://bugzilla.redhat.com/show_bug.cgi?id=524727
- http://roosbertl.blogspot.de/2012/12/centos6-disk-encryption-with-remote.html
- https://bitbucket.org/bmearns/dracut-crypt-wait
