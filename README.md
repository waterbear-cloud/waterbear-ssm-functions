# waterbear-ssm-functions

SSM Session helper BASH functions for creating and using SSH and Port Forwarding sessions.

## Example Usage

Create a BASH script that loads and uses the functions from the `waterbear-ssm-functions.sh` file.

*_/usr/local/bin/ssh-to-instance_*

>#!/bin/bash
>> 
>&#35; SSH Example
>
>&#35; Configuration
>
>NETENV_NAME=websites
>
>SSH_PRIVATE_KEY=~/.ssh/id_rsa
>
>&#35; Initialize functions
>
>&#35; Load the functions into scope
>
>. /path/to/helper/waterbear-ssm-functions.sh
>
>declare_environment <environment>
>
>declare_asg <application> <group> <resource> <username>
>
>ssm_command $@
