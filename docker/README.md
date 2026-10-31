# Docker

### Installation

sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg apt-transport-https lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io
sudo usermod -aG docker $USER
sudo usermod -aG sudo piholeuser

### Test Docker installation

docker run hello-world:latest

sudo systemctl status docker.service

### Stop and Restart Docker

sudo systemctl stop docker.service
sudo systemctl start docker.service

# References

https://www.howtogeek.com/devops/how-to-install-docker-and-docker-compose-on-linux/
https://medium.com/@piyushkashyap045/comprehensive-guide-installing-docker-and-docker-compose-on-windows-linux-and-macos-a022cf82ac0b
