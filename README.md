# waterbear-ssm-functions

SSM Session helper BASH functions for creating and using SSH and Port Forwarding sessions.

## Example Usage

Create a BASH script that loads and uses the functions from the `waterbear-ssm-functions.sh` file.

*_/usr/local/bin/ssh-to-instance_*

>#!/bin/bash
>> 
>&#35; SSH Example Configuration
>
>NETENV_NAME= \<netenv name\>
>
>SSH_PRIVATE_KEY=~/.ssh/id_rsa
>
>&#35; Initialize SSM functions
>
>. /path/to/helper/waterbear-ssm-functions.sh
>
>declare_environment \<environment\>
>
>declare_asg \<application\> \<group\> \<resource\> \<username\>
>
>ssm_command $@

### Usage

> $ /usr/local/bin/ssh-to-instance \<environment\> \<application\> \<group\> \<resource\> \<username\>
