# Script Arguments
ENVIRONMENT_ARG=$1
SERVER_ARG=$2
INSTANCE_ID_ARG=$3

declare -a ENVIRONMENT_ALIAS=()
declare -a ENVIRONMENT_LIST
declare -a SERVER_LIST

function usage()
{
    echo "usage: $0 <environment> <server> [instance id]"
    echo
    echo "Environments:"
    for ENVIRONMENT in "${ENVIRONMENT_LIST[@]}"
    do
	echo -e "\t${ENVIRONMENT}"
    done
    echo
    echo -e "Servers:"    
    for SERVER in "${SERVER_LIST[@]}"
    do
	echo -e "\t${SERVER}"
    done
    
    exit 1
}

function declare_environment()
{
    ENVIRONMENT="$1"
    ALIAS="$2"

    if [ "$ALIAS" != "" ] ; then
	ALIAS_ITEM="$ENVIRONMENT=$ALIAS"
	ENVIRONMENT_ALIAS+=("$ALIAS_ITEM")
    fi
    ENVIRONMENT_LIST+=("$ENVIRONMENT")
}

function declare_server()
{
    SERVER="$1"

    SERVER_LIST+=("$SERVER")
}

function process_args()
{

    # Assert: Environment exists
    if [[ ! " ${ENVIRONMENT_LIST[*]} " =~ " ${ENVIRONMENT_ARG} " ]]; then
	usage
    fi
    
    if [[ ! " ${SERVER_LIST[*]} " =~ " ${SERVER_ARG} " ]]; then
	usage
    fi   
    
    # Map the Alias environment
    for ALIAS_KVP in "${ENVIRONMENT_ALIAS[@]}"
    do
	ALIAS=$(echo $ALIAS_KVP | cut -d '=' -f 1)
	if [ "$ALIAS" == "$ENVIRONMENT_ARG" ] ; then
	    ENVIRONMENT_ARG=$(echo $ALIAS_KVP | cut -d '=' -f 2)
	    SUB_ENVIRONMENT="$ENVIRONMENT-"
	    break
	fi
    done
}

function get_unique_port()
{
    ENVIRONMENT=$1
    SERVER=$2
    
    # User Ports Range
    PORT_START=40000
    PORT_END=49151

    CALLER=$(basename $(caller | awk '{print $2}'))

    PORT_FILE_FOLDER=~/.paco-ssh
    PORT_FILE="${PORT_FILE_FOLDER}/ssh-local-ports"
    PORT_CACHE_FILE="${PORT_FILE_FOLDER}/${PROJECT_NAME}-${ENVIRONMENT}-${SERVER}.cache"
    if [ ! -e "$PORT_FILE" ] ; then
	mkdir -p $PORT_FILE_FOLDER
	:> $PORT_FILE
    fi
    if [ -e "$PORT_CACHE_FILE" ] ; then
	PORT=$(cat $PORT_CACHE_FILE)
	echo $PORT
	return 0
    fi
    PORT=$PORT_START
    while :
    do
	grep "|$PORT|" $PORT_FILE >/dev/null 2>&1
	RET=$?
	if [ $RET -eq 1 ] ; then
	    echo $PORT
	    echo "|$PORT|" >>$PORT_FILE
	    echo "$PORT" >$PORT_CACHE_FILE
	    return 0
	fi
	PORT=$(($PORT+1))
	if [ $PORT -gt $PORT_END ] ; then
	    echo "END-OF-LIST"
	    return 1
	fi
    done
}

function ssh_command()
{
    # Process Command Arguments
    process_args
    # Generate a local port to use    
    LOCAL_PORT=$(get_unique_port $ENVIRONMENT_ARG $SERVER_ARG)
        
    ENVIRONMENT_U=$(tr '[:lower:]' '[:upper:]' <<< ${ENVIRONMENT_ARG:0:1})${ENVIRONMENT_ARG:1}
    SERVER_U=$(tr '[:lower:]' '[:upper:]' <<< ${SERVER_ARG:0:1})${SERVER_ARG:1}
    PROJECT_U=$(tr '[:lower:]' '[:upper:]' <<< ${PROJECT_NAME:0:1})${PROJECT_NAME:1}
    APPLICATION_U=$(tr '[:lower:]' '[:upper:]' <<< ${APPLICATION_NAME:0:1})${APPLICATION_NAME:1}
    
    # Upper case ENVIRONMENT
    SERVER_NAME="${PROJECT_U}-${ENVIRONMENT_U}-${APPLICATION_U}-${SUB_ENVIRONMENT}${SERVER_U}-Server"
    AWS_PROFILE="${PROJECT_NAME}-$ENVIRONMENT_ARG"
    
    if [ "$INSTANCE_ID_ARG" != "" ] ; then
	SERVER_NAME="$INSTANCE_ID_ARG"	
    fi
    echo ssm_ssh $AWS_PROFILE $SERVER_NAME $SSH_USERNAME $SSH_PRIVATE_KEY $LOCAL_PORT
    ssm_ssh $AWS_PROFILE $SERVER_NAME $SSH_USERNAME $SSH_PRIVATE_KEY $LOCAL_PORT    
}


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
    if [ "$INSTANCE_ID" == "None" -o "$INSTANCE_ID" == "" ] ; then
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
    COMMAND=$6
    COMMAND_SOURCE=$7
    COMMAND_DEST=$8

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
    if [ "$COMMAND" == "scp" ] ; then
	scp -P $LOCAL_PORT -i $SSH_PRIVATE_KEY -o "StrictHostKeyChecking no" $COMMAND_SOURCE $SSH_USER@localhost:$COMMAND_DEST
    elif [ "$COMMAND" == "scp-from" ] ; then
	scp -P $LOCAL_PORT -i $SSH_PRIVATE_KEY -o "StrictHostKeyChecking no" $SSH_USER@localhost:$COMMAND_SOURCE $COMMAND_DEST
    else
	ssh -p $LOCAL_PORT -i $SSH_PRIVATE_KEY -o "StrictHostKeyChecking no" $SSH_USER@localhost	
    fi

}

