
provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key   
  cloud_api_secret = var.confluent_cloud_api_secret 
}


resource "confluent_environment" "msk_cl_test" {
  display_name = "msk_cl_test_${random_id.id.id}"
}

resource "confluent_network" "peering" {
  display_name     = "Peering Network ${random_id.id.id}"
  cloud            = "AWS"
  region           = var.region
  cidr             = "10.1.0.0/16"
  connection_types = ["PEERING"]
  environment {
    id = confluent_environment.msk_cl_test.id
  }
}

resource "confluent_peering" "aws" {
  display_name = "AWS Peering"
  aws {
    account         = var.aws_account_id
    vpc             = aws_vpc.main.id
    routes          = [ aws_vpc.main.cidr_block ]
    customer_region = var.region
  }
  environment {
    id = confluent_environment.msk_cl_test.id
  }
  network {
    id = confluent_network.peering.id
  }
}

resource "confluent_kafka_cluster" "dedicated" {
  display_name = "inventory"
  availability = "SINGLE_ZONE"
  cloud        = confluent_network.peering.cloud
  region       = confluent_network.peering.region
  dedicated {
    cku = 1
  }
  environment {
    id = confluent_environment.msk_cl_test.id
  }
  network {
    id = confluent_network.peering.id
  }
}

resource "confluent_service_account" "app-manager" {
  display_name = "app-manager"
  description  = "Service account to manage 'inventory' Kafka cluster"

  depends_on = [
    confluent_kafka_cluster.dedicated
  ]

}


resource "confluent_role_binding" "app-manager-env-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.msk_cl_test.resource_name
}

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  disable_wait_for_ready = true
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.dedicated.id
    api_version = confluent_kafka_cluster.dedicated.api_version
    kind        = confluent_kafka_cluster.dedicated.kind

    environment {
      id = confluent_environment.msk_cl_test.id
    }
  }
}
