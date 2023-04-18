terraform {
	required_providers {
		aws = {
			source = "hashicorp/aws"
			version = "~> 4.0"
		}

                confluent = {
                  source  = "confluentinc/confluent"
                  version = "1.39.0"
                }
	}


}
