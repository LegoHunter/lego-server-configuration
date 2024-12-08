# Redpanda

### Redpanda Server Installation
On legolandcloud1 (10.0.0.10)
curl -1sLf 'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' | sudo -E bash && sudo apt install redpanda -y

### Redpanda Console Installation
On legolandcloud1 (10.0.0.10)
curl -1sLf 'https://dl.redpanda.com/nzc4ZYQK3WRGd9sy/redpanda/cfg/setup/bash.deb.sh' | sudo -E bash && sudo apt-get install redpanda-console -y

### Bootstrap broker
?? --> sudo rpk redpanda config bootstrap --self 0.0.0.0 --advertised-kafka 10.0.0.10 --ips 10.0.0.10,10.0.0.11,10.0.0.12 && sudo rpk redpanda config set redpanda.empty_seed_starts_cluster false

### Start/Stop Redpanda Server service
sudo systemctl start redpanda-tuner redpanda
sudo systemctl stop redpanda-tuner redpanda

### Check Redpanda Server logs:
systemctl status redpanda.service
journalctl -xeu redpanda.service

### Start/Stop Redpanda Console service
sudo systemctl start redpanda-console
sudo systemctl stop redpanda-console

### Check Redpanda Console Server logs:
systemctl status redpanda-console
journalctl -xeu redpanda-console

### Check status of Redpanda Console service
sudo systemctl status redpanda-console

### Access Redpanda Console
http://legolandcloud1:8080/overview

### Useful rpk commands

`rpk cluster info`
`rpk cluster health`

Produce messages from commandline to a topic
`rpk topic product <topic-name>`

### /etc/redpanda/redpanda.yaml

```yaml
redpanda:
    data_directory: /var/lib/redpanda/data
    empty_seed_starts_cluster: false
    seed_servers:
        - host:
            address: 10.0.0.10
            port: 33145
        - host:
            address: 10.0.0.11
            port: 33145
        - host:
            address: 10.0.0.12
            port: 33145
    rpc_server:
        address: 0.0.0.0
        port: 33145
    kafka_api:
        - address: 0.0.0.0
          port: 9092
    admin:
        - address: 0.0.0.0
          port: 9644
    advertised_rpc_api:
        address: 10.0.0.10
        port: 33145
    advertised_kafka_api:
        - address: 10.0.0.10
          port: 9092
    developer_mode: true
    auto_create_topics_enabled: true
    fetch_reads_debounce_timeout: 10
    group_initial_rebalance_delay: 0
    group_topic_partitions: 3
    log_segment_size_min: 1
    storage_min_free_bytes: 10485760
    topic_partitions_per_shard: 1000
    write_caching_default: "true"
rpk:
    overprovisioned: true
    coredump_dir: /var/lib/redpanda/coredump
pandaproxy: {}
schema_registry: {}
```

### /etc/redpanda/redpanda-console.yaml

```yaml
kafka:
  brokers:
    - 127.0.0.1:9092
```
