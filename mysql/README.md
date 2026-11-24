# MySQL

**Backup:** a nightly dump of every application schema, kept off rasppi5-01. See [`backup/README.md`](backup/README.md) for what is backed up, how to restore, and the runbook.

### Installation

sudo apt update
sudo apt install mysql-server

sudo nano /etc/mysql/mysql.conf.d/mysqld.cnf
change this line to be:
bind-address            = 0.0.0.0

sudo systemctl start mysql.service
sudo systemctl status mysql.service

sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'password';
exit;

mysql -u root -p
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
exit;

sudo mysql_secure_installation
systemctl restart mysql.service

### Resources

https://www.digitalocean.com/community/tutorials/how-to-install-mysql-on-ubuntu-20-04
https://stackoverflow.com/questions/16287559/mysql-adding-user-for-remote-access
systemctl status mysql.service

### Initial account setup

sudo mysql -u root
CREATE USER 'tvattima'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON *.* TO 'tvattima'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
exit;

sudo reboot

### Accounts

Accounts and their rights are set up by the scripts in [accounts/](accounts/README.md)
(HOMELAB-126). Do not create accounts by hand, and never grant an account rights on `*.*`.
`legomgr` is for the legacy command-line tools and reaches `lego_prod_legacy` only.

### Common mysql commandline commands

#### Show all users
SELECT user,host FROM mysql.user;

#### Show all databases
SHOW DATABASES;

### Starting/Stopping/Restarting MySQL
systemctl status mysql.service
systemctl stop mysql.service
systemctl start mysql.service
systemctl restart mysql.service

### Completely Uninstalling MySQL

# sudo systemctl stop mysql
# sudo apt purge mysql-server mysql-client mysql-common mysql-server-core-* mysql-client-core-*
# sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
# sudo apt autoremove && sudo apt autoclean
# sudo apt remove dbconfig-mysql

