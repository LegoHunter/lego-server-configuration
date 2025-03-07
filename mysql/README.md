# MySQL

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

### Setting up lego_dev database and legomgr account

sudo mysql -u root
create database lego_dev;
CREATE USER 'legomgr'@'%' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON lego_dev.* TO 'legomgr'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
exit;

### Common mysql commandline commands

#### Show all users
SELECT user FROM mysql.user;



### Starting/Stopping/Restarting MySQL
systemctl status mysql.service
systemctl stop mysql.service
systemctl start mysql.service
systemctl restart mysql.service