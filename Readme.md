# Confluent Cluster Linking usage with MSK

The aim for this repo is to quickly demonstrate how easy it can be to initiate the migration from MSK to [Confluent Cloud](https://confluent.cloud) by leveraging [Confluent Cluster Linking](https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/index.html).

It's spinning up a couple of resources:
On the AWS side:
- A VPC with 3 subnets
- A bastion host, basic and elligible for for the AWS free tiers
- An internet gateway
- An MSK cluster
On the Confluent Cloud side:
- A environment in your organizatiion
- A network with a peering request to the VPC created above
- A dedicated Confluent Cloud cluster hosted in this network
- A service account and an API key to administrate the cluster

In order to make it look like what I can see from the field, both Kafka clusters are created to use only private networking, but to make it possible, this scenario supports only VPC peering between Confluent Cloud and the AWS VPC.

In order to set all of that up in an automated manner, it's using Terraform with the [Terraform provider for Confluent Cloud](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs). 

## Prerequisites

- Create a cloud API key for your Confluent Cloud orgnization, refer to [this](https://docs.confluent.io/cloud/current/access-management/authenticate/api-keys/api-keys.html#cloud-cloud-api-keys) for more information.
- This Terraform module requires a couple of variables: `aws_profile`, `aws_account_id`, `region`, `owner` (for naming resources) and `public_key_file_path` that points to an SSH public key to deploy to the bastion, for a demo like that, please basically use  `~/.ssh/id_rsa.pub`, as it avoids to explicitely define which private key file to use for every remote shell command. You can pass all of that in the command line, but I prefer using a `terraform.tfvars`:
```
aws_profile="800000000000005/bruce-wayne"
aws_account_id="800000000005"
owner="BriceLeporini"
region="me-south-1"
public_key_file_path="~/.ssh/id_rsa.pub"
```

## Run it!

Usually I try to use Docker instead of installing multiple tools on my laptop or to make it work everywhere quite easily, this is why you'll find a `terrform.sh` script which is using the official Hashicorp Terraform image.

The demo is broken down in a couple of  easy steps:

### Run the Terraform module

Considering you created the `terraform.tfvars` file in the same directory, you only need to export the Confluent Cloud API keys and secret and run terraform:

```bash
$ export CONFLUENT_CLOUD_API_KEY=JDyyyyyyyyyyGHAR
$ export CONFLUENT_CLOUD_API_SECRET=CL6qjffonlLxxxxxxxxxx6sj2f406Os7ANRUqf+u1tvStDRZW4siOO6UwWi/uMrr
$ ./terraform.sh apply
[...]
Plan: 25 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + bastion_ip = (known after apply)
  + msk        = (known after apply)

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

```

The outcome of this is a couple of files that will be utilized afterwards:
- `ccloud.properties` that contains all parameters to the newly created Confluent Cloud cluster
- `source-msk.properties` wich has the parameters to connect to the MSK cluster
- `bastion.sh` is a utility script to easily connect to the bastion host
- `create_link.sh` uploads the properties file to the bastion, and run remote command in order to create the link and the mirror for the source topic. **Note: As we're using VPC peering, the Cluster Link commands requires to be run from the VPC peered with the Confluent Cloud VPC, this is why this script uses remote commands.**

*It can happen that the excutions fails with the message below, in that case, just run it again, Terraform will synchronize all resources, that's why it's cool!*
```
│ Error: Provider produced inconsistent final plan
│
│ When expanding the plan for aws_vpc.main to include new values learned so far during apply, provider "registry.terraform.io/hashicorp/aws" produced an invalid new value for
│ .tags_all: new element "Name" has appeared.
│
│ This is a bug in the provider, which should be reported in the provider's own issue tracker.
```
*If it's not a bug in the provider and you knwo why it happens, a PR is more than welcome!*.

### Check it

The bastion host is created with a startup script that installs some dependencies and more importantly that creates a topic and starts a `kafka-producer-perf-test` to generate traffic on the MSK cluster, but it can take some time (~1 minute more or less) to download everything, so check that the performance test is running properly:

```bash
$ ./bastion.sh
Last login: Tue Apr 18 14:49:37 2023 from bba-2-49-41-36.alshamil.net.ae

       __|  __|_  )
       _|  (     /   Amazon Linux 2 AMI
      ___|\___|___|

https://aws.amazon.com/amazon-linux-2/
1 package(s) needed for security, out of 1 available
Run "sudo yum update" to apply all updates.
[ec2-user@ip-10-0-9-4 ~]$ docker ps
CONTAINER ID   IMAGE                   COMMAND                  CREATED              STATUS              PORTS      NAMES
d705e8613ddb   confluentinc/cp-kafka   "kafka-producer-perf…"   About a minute ago   Up About a minute   9092/tcp   nice_meninsky
[ec2-user@ip-10-0-9-4 ~]$ docker logs d705e8613ddb
4999 records sent, 999.6 records/sec (0.95 MB/sec), 24.1 ms avg latency, 542.0 ms max latency.
5001 records sent, 1000.2 records/sec (0.95 MB/sec), 5.6 ms avg latency, 49.0 ms max latency.
5001 records sent, 1000.2 records/sec (0.95 MB/sec), 5.4 ms avg latency, 65.0 ms max latency.
5007 records sent, 1001.2 records/sec (0.95 MB/sec), 5.7 ms avg latency, 38.0 ms max latency.
5002 records sent, 1000.4 records/sec (0.95 MB/sec), 2.9 ms avg latency, 41.0 ms max latency.
5001 records sent, 1000.2 records/sec (0.95 MB/sec), 2.2 ms avg latency, 17.0 ms max latency.
5001 records sent, 1000.2 records/sec (0.95 MB/sec), 2.3 ms avg latency, 21.0 ms max latency.
5001 records sent, 1000.2 records/sec (0.95 MB/sec), 2.1 ms avg latency, 22.0 ms max latency.
5001 records sent, 1000.2 records/sec (0.95 MB/sec), 2.5 ms avg latency, 26.0 ms max latency.
4997 records sent, 999.4 records/sec (0.95 MB/sec), 2.2 ms avg latency, 23.0 ms max latency.
5005 records sent, 1001.0 records/sec (0.95 MB/sec), 2.8 ms avg latency, 23.0 ms max latency.
5000 records sent, 1000.0 records/sec (0.95 MB/sec), 2.2 ms avg latency, 28.0 ms max latency.
5001 records sent, 1000.2 records/sec (0.95 MB/sec), 2.5 ms avg latency, 39.0 ms max latency.
5000 records sent, 1000.0 records/sec (0.95 MB/sec), 2.6 ms avg latency, 40.0 ms max latency.
4995 records sent, 998.8 records/sec (0.95 MB/sec), 4.3 ms avg latency, 46.0 ms max latency.
[ec2-user@ip-10-0-9-4 ~]$ ^C
``` 
If it's not working yes, disconnect and reconnect a few seconds later, just in case the `ec2-user` is not yet assigned the required group to use Docker.

### Create the link between the clusters

The performance utility is producing random strings in a topic named `test`, now you can run (from your laptop, it manages the remote commands) the `create_link.sh` script to create the link and start mirroring this topic:

```bash
$ ./create_link.sh                                                                                                                                                ✘ 130
ccloud.properties                                                                                                                                   100%  636    37.6KB/s   00:00
source-msk.properties                                                                                                                               100%  208    11.7KB/s   00:00
Unable to find image 'confluentinc/cp-server:7.3.0' locally
7.3.0: Pulling from confluentinc/cp-server
[...] 
Status: Downloaded newer image for confluentinc/cp-server:7.3.0
[2023-04-18 14:51:55,931] WARN These configurations '[acks, session.timeout.ms]' were supplied but are not used yet. (org.apache.kafka.clients.admin.AdminClientConfig)
Cluster link 'msk_lnk' creation successfully completed.
[2023-04-18 14:52:01,597] WARN These configurations '[acks, session.timeout.ms]' were supplied but are not used yet. (org.apache.kafka.clients.admin.AdminClientConfig)
Created topic test.
$
```

Then to verify that the link is effective, you can consume the `test` topic from the Confluent Cloud cluster:
```bash 
$ ./bastion.sh
[ec2-user@ip-10-0-9-4 ~]$ docker run -ti --rm -v $PWD:/work confluentinc/cp-server:7.3.0 kafka-console-consumer --bootstrap-server <Confluent Cloud cluster> --consumer.config /work/ccloud.properties --topic test 
[2023-04-18 14:53:23,439] WARN These configurations '[acks]' were supplied but are not used yet. (org.apache.kafka.clients.consumer.ConsumerConfig)
YCIOTCECWIOGNEXWMCUFIYGYNWDTOEWBMPMOAQMSYXXYPMAPDBSZGBKWIJRKMLCOJLSBQQJYOEJNWDMMQUQGPKANUGNGLMTDZGQJBWZITDQGUCIEDFWHCIRIVNJSPSGXSGOQNAHKKBLTGNVDMGOVGRKNPBFVHMHGHUCFPSDLRQFKPDCECILZOWDZHGRQWKNCTYIFATNXQSEDPPKNGBOPYWLCWFZAUNSZUKESAZJEYQQDARILCZDYYLZOOIRZACTZMPAMFEXKVWTPZMJKXLJPRGSTJHLGFXYHUDLNXVYNJCXPFLKPPVZSOCQBCFLENNFRIYIUSPOBNPFXWMSNWPPONVKLXXRSCVRFMLTGCYRPGTAGJQGSRWGLMZIFUWWVNPMTPGDTKJYDMMQYLUNGUQGLSVFZDZMBJIYBUTGNBPARFEEYSUNMSLEGUVYDSBOHSHCHJYWPBJFUUUJVSPHHPKYYMUMLXRUBXQFIGSVTAOSJWUJTAEUDTZJMBOWIQTKNSIVGQFZGZSZSASTDJPZXBSNIUBLIBDXJLIGBKHFJFKYKDVTGLROFWAOLHCEXOOZXCMBTPPTGVOAXEFTNCVAYAXOGZQLVDZOGXPSYSHSANHKRJTDPBURIDVXQOLNASQEYQOHFSTZKPAPPYBCZHGOWAFBCQMIRMOEKHYJWXKCRYHOZBNSCLWOVLDOSJWFKBUJRCRELNAEALFQQIJUONLWTHDIVVDEMPZPANILCFNZAWPUXJVWUNHPMQPSYIAUOJZSPHOUFOADEUGPVIAODSLMZGMMANEZJWSEVKBKBFBIUBCSXQURYZUWUIOBKRCFUEQPQTAXANOSLNSEZZMVONAXNHRROGLLTHCOCRYKXRLOQOJSUTKXVMSGOHGOBEJTTVYKLMAIZJRKRYBOMTCLESBBZGPDTHAVIPWLCWAYXTNFVBZRFAVHMHTRERWAWVPOYOLSFOSLBECAIMCTXEHLPGJWVUSTKIZXMUPZAVHMMHGLCYGVR
[...]
Processed a total of 776 messages
[ec2-user@ip-10-0-9-4 ~]$
```

Hit `CTRL-C` after a few seconds otherwise your terminal will be flooded, but it shows that the link is actually mirroring the content of the source topic. 


### Dispose everything

It's just simple as: 

```bash
$ ./terraform.sh destroy
Plan: 0 to add, 0 to change, 25 to destroy.

Changes to Outputs:
  - bastion_ip = "157.175.168.165" -> null
  - msk        = "b-1.msk.c9akvi.c3.kafka.me-south-1.amazonaws.com:9092,b-2.msk.c9akvi.c3.kafka.me-south-1.amazonaws.com:9092,b-3.msk.c9akvi.c3.kafka.me-south-1.amazonaws.com:9092" -> null

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes
```

