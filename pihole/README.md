# Pi-hole, Unbound, Nebula-Sync

### Installation

sudo apt install curl -y

sudo useradd -m -s /bin/bash piholeuser
sudo passwd piholeuser
sudo usermod -aG sudo piholeuser
sudo nano visudo
Add at bottom of file: `piholeuser  ALL=(ALL) NOPASSWD:ALL`
Save and exit nano

sudo mkdir -p /opt/stacks/pihole
sudo chown piholeuser:piholeuser /opt/stacks/pihole
sudo setfacl -m user:piholeuser:rw /var/run/docker.sock
su - piholeuser

sudo curl -sSL https://install.pi-hole.net | bash
pihole setpassword
sudo reboot now

sudo apt install unbound -y
cd /etc/unbound/unbound.conf.d
sudo nano pi-hole.conf
Copy the contents of `https://docs.pi-hole.net/guides/dns/unbound/#configure-unbound`
Save and exit nano

service unbound restart
sudo reboot now

Update Pi-hole DNS to use Custom DNS servers: `127.0.0.1#5335`

### Test Pi-hole / Unbound installation

dig pi-hole.net @127.0.0.1 -p 5335
dig fail01.dnssec.works @127.0.0.1 -p 5335
dig dnssec.works @127.0.0.1 -p 5335

### Stop and Restart Pi-hole

sudo systemctl restart pihole-FTL
sudo systemctl stop pihole-FTL
sudo systemctl start pihole-FTL

### Stop and Restart Unbound

service unbound stop
service unbound start

### Recreating Unbound DNS root.key

This may need to be done if weird DNS errors start occurring.
Tail the Pi-hole pihole.log file and check for errors such as:

```
SERVFAIL
```

service unbound stop
sudo rm /var/lib/unbound/root.key
sudo unbound-anchor -a /var/lib/unbound/root.key
service unbound start
sudo systemctl restart pihole-FTL

## Updating Lists

After updating lists, run as piholeuser: `sudo pihole -g`

# References

https://www.wundertech.net/ultimate-pi-hole-setup/
https://ronamosa.io/docs/engineer/LAB/pihole-docker-unbound/
https://docs.pi-hole.net/guides/dns/unbound/#configure-unbound

https://technotim.live/posts/pihole-sync-nebula/

https://www.youtube.com/watch?v=OcSBggDyeJ4
https://www.youtube.com/watch?v=6sznCZ7ttbI