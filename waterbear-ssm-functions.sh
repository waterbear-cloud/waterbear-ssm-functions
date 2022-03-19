function valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function cache_mfa()
{
    AWS_PROFILE=$1
    
    aws ssm start-session --profile $AWS_PROFILE --target null 2>/dev/null
}

function get_target_instance_id()
{
    AWS_PROFILE=$1
    SERVER_NAME=$2

    FILTER=Name=tag:Name,Values=$SERVER_NAME    
    if valid_ip $SERVER_NAME; then 
	FILTER="Name=network-interface.addresses.private-ip-address,Values=$SERVER_NAME"
    fi

    echo aws ec2 describe-instances --profile $AWS_PROFILE --query "Reservations[0].Instances[*].[InstanceId]" --filters $FILTER Name=instance-state-name,Values=running --output text  >/tmp/aws.out
    aws ec2 describe-instances --profile $AWS_PROFILE --query "Reservations[0].Instances[*].[InstanceId]" --filters $FILTER Name=instance-state-name,Values=running --output text 
}

function ssm_ssh_session()
{
    AWS_PROFILE=$1
    SERVER_NAME=$2    

    INSTANCE_ID=$(get_target_instance_id $AWS_PROFILE $SERVER_NAME)

    aws ssm start-session --profile $AWS_PROFILE --target $INSTANCE_ID
}

function ssm_port_forward()
{
    #echo "Starting session for instance: $2 on port $1"
    AWS_PROFILE=$1
    SERVER_NAME=$2
    LOCAL_PORT=$3
    REMOTE_PORT=$4

    INSTANCE_ID=$(get_target_instance_id $AWS_PROFILE $SERVER_NAME)
    if [ "$INSTANCE_ID" == "None" ] ; then
	echo "ERROR: Unable to get Instance ID for Server Name: $SERVER_NAME"
	exit 1
    fi

    echo "Connecting localhost:$LOCAL_PORT to $INSTANCE_ID:$REMOTE_PORT"

    echo aws ssm start-session --document-name AWS-StartPortForwardingSession --parameters "localPortNumber=$LOCAL_PORT,portNumber=$REMOTE_PORT" --profile $AWS_PROFILE --target $INSTANCE_ID
    aws ssm start-session --document-name AWS-StartPortForwardingSession --parameters "localPortNumber=$LOCAL_PORT,portNumber=$REMOTE_PORT" --profile $AWS_PROFILE --target $INSTANCE_ID
}

function ssm_ssh()
{
    AWS_PROFILE=$1
    SERVER_NAME=$2    
    SSH_USER=$3
    SSH_PRIVATE_KEY=$4
    LOCAL_PORT=$5

    SSM_LOG=/tmp/ssm_ssh.log

    cache_mfa $AWS_PROFILE

    ps awux |grep session-manager-plugin |grep "localPortNumber\": \[\"${LOCAL_PORT}\"" >/dev/null 2>&1
    if [ $? -ne 0 ] ; then
	ssm_port_forward $AWS_PROFILE $SERVER_NAME $LOCAL_PORT 22 >$SSM_LOG 2>&1 &
	COUNT=0
	TIMEOUT_SECS=20
	while :
	do
	    grep "bind: address already in use" $SSM_LOG >/dev/null 2>&1
	    if [ $? -eq 0 ] ; then
		echo "ERROR: Session already started on localhost:$LOCAL_PORT"
		cat $SSM_LOG
		exit 1
	    fi
	    grep "Waiting for connections" $SSM_LOG >/dev/null 2>&1
	    if [ $? -eq 0 ] ; then
		echo "Opening SSH connection on new session: localhost:$LOCAL_PORT"
		break
	    fi
	    grep "An error occurred" $SSM_LOG >/dev/null 2>&1
	    if [ $? -eq 0 ] ; then
		echo "ERROR: Unable to open SSM session"
		cat $SSM_LOG
		exit 1
	    fi
	    if [ $COUNT -eq $TIMEOUT_SECS ] ; then
		echo "ERROR: Timedout waiting for ssm session:"
		cat $SSM_LOG
		exit 1
	    fi
	    COUNT=$(($COUNT + 1))
	    sleep 1
	done
    else
	echo "Opening SSH connection on existing session: localhost:$LOCAL_PORT"
    fi

    ssh-keygen -R [localhost]:$LOCAL_PORT >>$SSM_LOG 2>&1
    ssh -p $LOCAL_PORT -i $SSH_PRIVATE_KEY -o "StrictHostKeyChecking no" $SSH_USER@localhost

}

