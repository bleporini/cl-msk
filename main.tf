

provider "aws" {
  region = var.region
  profile = var.aws_profile
  default_tags{
    tags = {
  	Owner = var.owner
    }
  }
}


resource "random_id" "id" {
  byte_length = 4
}



resource "aws_vpc" "main"{
  cidr_block = "10.0.0.0/16"
  
  tags = {
	Name = "vpc_${var.owner}_${random_id.id.id}"
  }
}

resource "aws_subnet" "subnet" {
  for_each = {
    a = "0"
    b = "16"
    c = "32"
  }

  vpc_id = aws_vpc.main.id
  cidr_block = "10.0.${each.value}.0/20"
  availability_zone = "${var.region}${each.key}"
}

resource "aws_key_pair" "pub_key" {
  key_name = "pub_${random_id.id.id}"
  public_key = "${data.template_file.public_key.rendered}"
}

data "aws_ami" "amzn_lnx" {
  name_regex = "amzn2-ami-kernel-5.10*"
  most_recent = true

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name = "architecture"
    values = ["x86_64"]
  }

  filter {
    name = "owner-alias"
    values = ["amazon"]
  }
}

resource "aws_security_group" "allow_ssh" {
  name = "allow_ssh"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]

  }
}

resource "aws_security_group" "allow_p8s" {
  name = "allow_p8s"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 9090
    to_port = 9090
    protocol = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]

  }
}

resource "aws_security_group" "allow_ccloud" {
  name = "allow_cloud"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 0
    to_port = 9092
    protocol = "tcp"
    cidr_blocks      = ["10.1.0.0/16"]
  }
}

resource "aws_instance" "bastion" {
  ami = data.aws_ami.amzn_lnx.id
  instance_type = "t3.micro"
  associate_public_ip_address = true
 
  subnet_id = aws_subnet.subnet["a"].id

  security_groups = [
    aws_security_group.allow_ssh.id,
    aws_security_group.allow_p8s.id,
    aws_vpc.main.default_security_group_id
  ]
  key_name = "pub_${random_id.id.id}"

  user_data = <<EOF
#!/usr/bin/env bash

sudo yum install -y docker 
sudo systemctl start docker
sudo usermod -a -G docker ec2-user

docker run  confluentinc/cp-kafka kafka-topics --bootstrap-server ${aws_msk_cluster.msk.bootstrap_brokers} --create --topic test 
docker run -d --name producer confluentinc/cp-kafka kafka-producer-perf-test --producer-props bootstrap.servers=${aws_msk_cluster.msk.bootstrap_brokers} --num-records 100000000 --record-size 1000 --throughput 1000 --topic test  
docker run -d --name consumer confluentinc/cp-kafka kafka-consumer-perf-test --bootstrap-server ${aws_msk_cluster.msk.bootstrap_brokers} --messages 100000000 --topic test --group client1 

EOF

  tags = {
    Name = "bastion"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "igw_${random_id.id.id}"
  }
}

resource "aws_route" "gw" {
  route_table_id            = aws_vpc.main.main_route_table_id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

data "aws_vpc_peering_connection" "accepter" {
  vpc_id      = confluent_network.peering.aws[0].vpc
  peer_vpc_id = confluent_peering.aws.aws[0].vpc
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  vpc_peering_connection_id = data.aws_vpc_peering_connection.accepter.id
  auto_accept               = true
}

resource "aws_route" "peering" {
  route_table_id            = aws_vpc.main.main_route_table_id
  destination_cidr_block    = confluent_network.peering.cidr
  vpc_peering_connection_id = data.aws_vpc_peering_connection.accepter.id
}

resource "aws_msk_cluster" "msk" {
  cluster_name           = "msk"
  kafka_version          = "3.2.0"
  number_of_broker_nodes = 3

  client_authentication { 
    unauthenticated = true 
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
    }
  }

  broker_node_group_info {
    instance_type = "kafka.m5.large"
    client_subnets = [
      aws_subnet.subnet["a"].id,
      aws_subnet.subnet["b"].id,
      aws_subnet.subnet["c"].id,
    ]
    storage_info {
      ebs_storage_info {
        volume_size = 1000
      }
    }
    security_groups = [aws_vpc.main.default_security_group_id, aws_security_group.allow_ccloud.id]
  }
}
