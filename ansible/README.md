## Ansible

### create sysadmin user
sudo adduser sysadmin && sudo usermod -aG sudo sysadmin && su - sysadmin

touch /etc/sudoers.d/sysadmin && cat "sysadmin ALL = NOPASSWD : ALL" > /etc/sudoers.d/sysadmin

### Install net-tools
sudo apt install nmap
sudo apt install net-tools

## Setup Python virtual environment
sudo apt install python3.13-venv
cd ~
python3 -m venv ansible-env
source ~/ansible-env/bin/activate

### Install Python packages
pip install PyYAML

### Install Ansible
sudo apt update && sudo apt upgrade -y
sudo apt install software-properties-common python3 python3-pip
sudo apt-add-repository --yes --update ppa:ansible/ansible  
sudo apt install ansible

### Test Ansible installation
ansible --version
ansible all -m ping -i "localhost," -c local

### Install Ansible Galaxy Collections
ansible-galaxy collection install community.general

### populate arp table
nmap -sP 10.0.2.1/24
arp -an

### Ansible Playbook Commands
ansible-playbook -i inventory.ini playbook.yml --ask-become-pass