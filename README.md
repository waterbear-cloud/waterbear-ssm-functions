# waterbear-ssm-functions

SSM Session helper BASH functions for creating and using SSH and Port Forwarding sessions.

## Example Usage

Create a BASH script that loads and uses the functions from the `waterbear-ssm-functions.sh` file.

*_/usr/local/bin/ssh-to-instance_*

>#!/bin/bash
>
># Load the functions into scope
>. /path/to/helper/waterbear-ssm-functions.sh
> 
># SSH Example
>ssm_ssh <aws_profile> <server_name> <ec2 user> <ssh_private_key_file> <local_port>

The `ssm_ssh()` function will start an SSM Session using the AWS CLI to setup port forwarding on `localhost:<local_port>` to port 22 on the instance identified by `<server_name>`.

*_/usr/local/bin/ssm-database-port-forward_*

>#!/bin/bash
>
># Load the functions into scope
>. /path/to/helper/waterbear-ssm-functions.sh
>
># Port forwarding example
>ssm_port_forward <aws_profile> <server_name> <local_port> <remote_port>

The `ssm_port_forward()` function will start an SSM Session using the AWS CLI to port forward `localhost:<local_port>` to the `<remote_port>` on the EC2 instance identified by `<server_name>`.






