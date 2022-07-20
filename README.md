# waterbear-ssm-functions

SSM Session helper BASH functions for creating and using SSH and Port Forwarding sessions.

## Example Usage

Create a BASH script that loads and uses the functions from the `waterbear-ssm-functions.sh` file.

*_/usr/local/bin/ssh-to-instance_*

>#!/bin/bash
>> 
>&#35; SSH Example
>
># Configuration
>NETENV_NAME=websites
>APPLICATION_NAME=workloads
>AWS_PROFILE_PREFIX=askmed
>SSH_USERNAME=ec2-user
>SSH_PRIVATE_KEY=~/.ssh/askmed_key_rsa
>#SSH_PRIVATE_KEY=~/Documents/WaterbearCloud/WaterbearCloud/credentials/wbsites-cloud-dev-us-west-2.pem
>
># Initialize functions
>&#35;  Load the functions into scope
>
>. /path/to/helper/waterbear-ssm-functions.sh
>
>declare_environment prod
>declare_environment test
>
>declare_asg oscar_terminal_app server
>
>ssm_command $@
