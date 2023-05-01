output "bastion_ip"{
  value = aws_instance.bastion.public_ip
} 

resource "local_file" "bastion" {
  content=<<EOF
#!/usr/bin/env bash
ssh ec2-user@${aws_instance.bastion.public_ip}
  EOF

  filename="bastion.sh"
}


output "msk"{
  value = aws_msk_cluster.msk.bootstrap_brokers
}

resource "local_file" "msk_config" {
  content=<<EOF
bootstrap.servers=${aws_msk_cluster.msk.bootstrap_brokers}
security.protocol=PLAINTEXT
consumer.offset.sync.enable=true
EOF

  filename="source-msk.properties"
}

resource "local_file" "ccloud_config"{
  content=<<EOF
# Required connection configs for Kafka producer, consumer, and admin
bootstrap.servers=${replace(confluent_kafka_cluster.dedicated.bootstrap_endpoint, "SASL_SSL://", "")}
security.protocol=SASL_SSL
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${confluent_api_key.app-manager-kafka-api-key.id}' password='${confluent_api_key.app-manager-kafka-api-key.secret}';
sasl.mechanism=PLAIN
# Required for correctness in Apache Kafka clients prior to 2.6
client.dns.lookup=use_all_dns_ips

# Best practice for higher availability in Apache Kafka clients prior to 3.0
session.timeout.ms=45000

# Best practice for Kafka producer to prevent data loss
acks=all
  EOF

  filename= "ccloud.properties"
}

resource "local_file" "create_link"{
  content=<<EOF
#!/usr/bin/env bash
scp prometheus.yml ec2-user@${aws_instance.bastion.public_ip}:~/ 
ssh ec2-user@${aws_instance.bastion.public_ip} 'docker run -d -p 9090:9090 --name prometheus -v $PWD/prometheus.yml:/opt/bitnami/prometheus/conf/prometheus.yml bitnami/prometheus:latest'
scp ccloud.properties ec2-user@${aws_instance.bastion.public_ip}:~/
scp source-msk.properties ec2-user@${aws_instance.bastion.public_ip}:~/
scp link_group_filters.json ec2-user@${aws_instance.bastion.public_ip}:~/
ssh ec2-user@${aws_instance.bastion.public_ip} 'docker run -v $PWD:/work --workdir /work --rm confluentinc/cp-server:7.3.0 kafka-cluster-links --bootstrap-server=${replace(confluent_kafka_cluster.dedicated.bootstrap_endpoint, "SASL_SSL://", "")} --command-config ccloud.properties --config-file source-msk.properties --create --link msk_lnk --consumer-group-filters-json-file link_group_filters.json'
ssh ec2-user@${aws_instance.bastion.public_ip} 'docker run -v $PWD:/work --workdir /work --rm confluentinc/cp-server:7.3.0 kafka-mirrors --bootstrap-server ${replace(confluent_kafka_cluster.dedicated.bootstrap_endpoint, "SASL_SSL://", "")} --create --mirror-topic test --link msk_lnk --command-config ccloud.properties'
echo You can check out Prometheus on http://${aws_instance.bastion.public_ip}:9090
  EOF

  filename= "create_link.sh"

}

resource "local_file" "p8s_cfg"{
  content=<<EOF
scrape_configs:
  - job_name: Confluent Cloud
    scrape_interval: 1m
    scrape_timeout: 1m
    honor_timestamps: true
    static_configs:
      - targets:
        - api.telemetry.confluent.cloud
    scheme: https
    basic_auth:
      username: ${confluent_api_key.prometheus-cloud-api-key.id}
      password: ${confluent_api_key.prometheus-cloud-api-key.secret}
    metrics_path: /v2/metrics/cloud/export
    params:
      "resource.kafka.id":
        - ${confluent_kafka_cluster.dedicated.id}
  EOF

  filename="prometheus.yml"
}
