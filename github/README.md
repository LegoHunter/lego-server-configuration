## Github.com

### Self-Hosted Runner

Runs on legolandserver1

Setup github runner user group:
`sudo groupadd github-runner`

Setup github-runner user
`sudo useradd -m github-runner -g github-runner`

Set github-runner passwd
`sudo passwd github-runner`

Add github-runner to sudo group
`sudo usermod -aG sudo github-runner`

#### Installation:
https://github.com/organizations/LegoHunter/settings/actions/runners/new?arch=arm64&os=linux

**_Note_**: run commands as sudo

Running as a service in Linux

1. su github-runner
2. https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service

**_Note_**: when installing service, specify username as part of the command:
`sudo ./svc.sh install github-runner`

Checking Github Runner status:
`cd /etc/actions-runner`
`sudo ./svc.sh status`

#### Additional information
https://docs.github.com/en/actions/hosting-your-own-runners

### Actions