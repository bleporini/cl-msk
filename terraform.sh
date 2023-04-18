#!/usr/bin/env bash 

#set -x 
docker run -ti --rm -v $PWD:/work/terraform -v $PWD/../:/work --workdir /work/terraform \
	-v $HOME/.aws:/root/.aws \
	-v $HOME/.ssh/id_rsa.pub:/root/.ssh/id_rsa.pub \
	-e TF_VAR_confluent_cloud_api_key=$CONFLUENT_CLOUD_API_KEY \
	-e TF_VAR_confluent_cloud_api_secret=$CONFLUENT_CLOUD_API_SECRET \
	hashicorp/terraform:1.4.4 "$@"
	#--entrypoint "/bin/sh" hashicorp/terraform:1.4.4
	#-e TF_LOG=DEBUG \
	#-e TF_LOG=TRACE \
	#-e TF_LOG=DEBUG \
	#-e TF_LOG=ERROR \

