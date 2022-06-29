# SSM Functions
#
# ------------------------------------------
# # User Script Example
#
# # Configuration
# NETENV_NAME=<netenv name>
# APPLICATION_NAME=<app name>
# SSH_USERNAME=ec2-user
# SSH_PRIVATE_KEY=~/.ssh/id_rsa
#
# # Load the Functions
# . /path/to/waterbear-ssm-functions/waterbear-ssm-functions.sh
# 
# declare_environment prod
# declare_environment staging
# 
# declare_asg <group name> <resource name>
# 
# ssm_command $@
# ------------------------------------------


# Args
ENVIRONMENT_ARG=$1
shift
ASG_ARG=$1
shift
SERVER_ARG=$1
shift

# Args: Command and Instance IP
declare -a ENVIRONMENT_ALIAS
declare -a ENVIRONMENT_LIST
declare -a ASG_LIST


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

INSTANCE_IP_ARG=""
if valid_ip "$1"; then    
    INSTANCE_IP_ARG="$1"
    shift
fi

PORT_FILE_FOLDER=~/.paco-ssh
PORT_FILE="${PORT_FILE_FOLDER}/ssh-local-ports"
if [ "$INSTANCE_IP_ARG" != "" ] ; then
    INSTANCE_IP_CACHE="-${INSTANCE_IP_ARG}"
fi
PORT_CACHE_FILE="${PORT_FILE_FOLDER}/${NETENV_NAME}-${ENVIRONMENT_ARG}-${ASG_ARG}-${SERVER_ARG}${INSTANCE_IP_CACHE}.cache"
PORT_PID_CACHE_FILE="${PORT_CACHE_FILE}.port-pid"


function usage()
{
    echo "usage: $0 <environment> <asg> <server> [instance IP|scp]"
    echo
    echo "Environments:"
    for ENVIRONMENT in "${ENVIRONMENT_LIST[@]}"
    do
	echo -e "\t${ENVIRONMENT}"
    done
    echo
    echo -e "Servers:"
    for ASG_GRP in "${ASG_LIST[@]}"
    do
	ASG_NAME=$(echo $ASG_GRP | cut -d ':' -f 1)
	SERVER_NAME=$(echo $ASG_GRP | cut -d ':' -f 2)	
	echo -e "\t${ASG_NAME} ${SERVER_NAME}"
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

function declare_asg()
{
    GROUP="$1"
    ASG=$"$2"

    ASG_LIST+=($(echo "$GROUP:$ASG" | tr '_' '-'))
}

function process_args()
{
    
    # Assert: Environment exists
    if [[ ! " ${ENVIRONMENT_LIST[*]} " =~ " ${ENVIRONMENT_ARG} " ]]; then
	usage
    fi
    
    # Assert: ASG exists
    FOUND=0
    for ASG_GRP in "${ASG_LIST[@]}"
    do
	ASG_NAME=$(echo $ASG_GRP | cut -d ':' -f 1)
	SERVER_NAME=$(echo $ASG_GRP | cut -d ':' -f 2)
	if [ "$ASG_NAME" == "$ASG_ARG" -a "$SERVER_NAME" == "$SERVER_ARG" ] ; then
	    FOUND=1
	    break
	fi
    done
    if [ $FOUND -eq 0 ] ; then
	echo "ERROR: Unable to find ASG and Server: $ASG_ARG $SERVER_ARG"
	usage
    fi
    
    # Map the Alias environment
    PROFILE_ENVIRONMENT="$ENVIRONMENT_ARG"
    for ALIAS_KVP in "${ENVIRONMENT_ALIAS[@]}"
    do
	ALIAS=$(echo $ALIAS_KVP | cut -d '=' -f 1)
	if [ "$ALIAS" == "$ENVIRONMENT_ARG" ] ; then
	    ENVIRONMENT_ARG="$ENVIRONMENT"
	    PROFILE_ENVIRONMENT=$(echo $ALIAS_KVP | cut -d '=' -f 2)
	    break
	fi
    done
}


function get_unique_port()
{
    ENVIRONMENT=$1
    ASG=$2
    
    # User Ports Range
    PORT_START=40000
    PORT_END=49151

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

function ssm_command()
{
    COMMAND_ARG=$1
    shift

    if [ "$COMMAND_ARG" == "" ] ; then
	COMMAND_ARG="ssh"
    fi

    # Process Command Arguments
    process_args
    # Generate a local port to use
    LOCAL_PORT=$(get_unique_port $ENVIRONMENT_ARG $ASG_ARG)

    if [ "$SUB_ENVIRONMENT" == "" ] ; then
	ENVIRONMENT_U=$(tr '[:lower:]' '[:upper:]' <<< ${ENVIRONMENT_ARG:0:1})${ENVIRONMENT_ARG:1}
    else
	ENVIRONMENT_U=$(tr '[:lower:]' '[:upper:]' <<< ${SUB_ENVIRONMENT:0:1})${SUB_ENVIRONMENT:1}
    fi
    ASG_ARG_U=$(tr '[:lower:]' '[:upper:]' <<< ${ASG_ARG:0:1})${ASG_ARG:1}
    SERVER_ARG_U=$(tr '[:lower:]' '[:upper:]' <<< ${SERVER_ARG:0:1})${SERVER_ARG:1}
    PROJECT_U=$(tr '[:lower:]' '[:upper:]' <<< ${NETENV_NAME:0:1})${NETENV_NAME:1}
    APPLICATION_U=$(tr '[:lower:]' '[:upper:]' <<< ${APPLICATION_NAME:0:1})${APPLICATION_NAME:1}
    
    # Upper case ENVIRONMENT
    #ASG_NAME="${PROJECT_U}-${ENVIRONMENT_U}-${APPLICATION_U}-${SUB_ENVIRONMENT}${ASG_ARG_U}-${SERVER_ARG_U}"
    ASG_NAME="${PROJECT_U}-${ENVIRONMENT_U}-${APPLICATION_U}-${ASG_ARG_U}-${SERVER_ARG_U}"
    if [ "$AWS_PROFILE_PREFIX" == "" ] ; then
	AWS_PROFILE="${NETENV_NAME}-${PROFILE_ENVIRONMENT}"
    else
	AWS_PROFILE="${AWS_PROFILE_PREFIX}-${PROFILE_ENVIRONMENT}"
    fi

    if [ "$INSTANCE_IP_ARG" != "" ] ; then
	ASG_NAME="$INSTANCE_IP_ARG"	
    fi
    echo "COMMAND_ARG: $COMMAND_ARG"
    COMMAND=$COMMAND_ARG
    case $COMMAND_ARG in
	"scp") 
	    COMMAND_SOURCE=$1
	    shift
	    COMMAND_DEST=$1
	    shift
	    COMMAND=ssh
	    ;;	
	"scp-from") 
	    COMMAND_SOURCE=$1
	    shift
	    COMMAND_DEST=$1
	    shift	    
	    COMMAND=ssh
	    ;;	
    esac    

    INSTANCE_IP=$1
    shift
    case $COMMAND in
	"ssh")
	    echo ssm_ssh $AWS_PROFILE $ASG_NAME $SSH_USERNAME $SSH_PRIVATE_KEY $LOCAL_PORT $COMMAND_ARG $COMMAND_SOURCE $COMMAND_DEST
	    ssm_ssh $AWS_PROFILE $ASG_NAME $SSH_USERNAME $SSH_PRIVATE_KEY $LOCAL_PORT $COMMAND_ARG $COMMAND_SOURCE $COMMAND_DEST
	    ;;
	"port_forward")
	    REMOTE_PORT=$2
	    echo ssm_port_forward $AWS_PROFILE $ASG_NAME $LOCAL_PORT $REMOTE_PORT $INSTANCE_IP
	    ssm_port_forward $AWS_PROFILE $ASG_NAME $LOCAL_PORT $REMOTE_PORT $INSTANCE_IP
	    ;;	    
    esac
}


function cache_mfa()
{
    AWS_PROFILE=$1
    
    aws ssm start-session --profile $AWS_PROFILE --target null 2>/dev/null
}

function get_target_instance_id()
{
    AWS_PROFILE=$1
    ASG_NAME=$2

    FILTER=Name=tag:Name,Values=$ASG_NAME    
    if valid_ip $ASG_NAME; then
	FILTER="Name=network-interface.addresses.private-ip-address,Values=$ASG_NAME"
    fi

    aws ec2 describe-instances --profile $AWS_PROFILE --query "Reservations[0].Instances[*].[InstanceId]" --filters $FILTER Name=instance-state-name,Values=running --output text 
}

function ssm_ssh_session()
{
    AWS_PROFILE=$1
    ASG_NAME=$2    

    INSTANCE_ID=$(get_target_instance_id $AWS_PROFILE $ASG_NAME)

    aws ssm start-session --profile $AWS_PROFILE --target $INSTANCE_ID
}

function ssm_port_forward()
{
    #echo "Starting session for instance: $2 on port $1"
    AWS_PROFILE=$1
    ASG_NAME=$2
    LOCAL_PORT=$3
    REMOTE_PORT=$4

    INSTANCE_ID=$(get_target_instance_id $AWS_PROFILE $ASG_NAME)
    if [ "$INSTANCE_ID" == "None" -o "$INSTANCE_ID" == "" ] ; then
	echo "ERROR: Unable to get Instance ID for Server Name: $ASG_NAME"
	exit 1
    fi

    echo "Connecting localhost:$LOCAL_PORT to $INSTANCE_ID:$REMOTE_PORT"

    echo aws ssm start-session --document-name AWS-StartPortForwardingSession --parameters "localPortNumber=$LOCAL_PORT,portNumber=$REMOTE_PORT" --profile $AWS_PROFILE --target $INSTANCE_ID
    aws ssm start-session --document-name AWS-StartPortForwardingSession --parameters "localPortNumber=$LOCAL_PORT,portNumber=$REMOTE_PORT" --profile $AWS_PROFILE --target $INSTANCE_ID
}

function ssm_ssh()
{
    AWS_PROFILE=$1
    ASG_NAME=$2    
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
	ssm_port_forward $AWS_PROFILE $ASG_NAME $LOCAL_PORT 22 >$SSM_LOG 2>&1 &
	PID=$!
	COUNT=0
	TIMEOUT_SECS=20
	while :
	do
	    grep "bind: address already in use" $SSM_LOG >/dev/null 2>&1
	    if [ $? -eq 0 ] ; then
		echo "ERROR: Session already started on localhost:$LOCAL_PORT"
		cat $SSM_LOG
		rm -f $PORT_CACHE_FILE
		exit 1
	    fi
	    grep "Waiting for connections" $SSM_LOG >/dev/null 2>&1
	    if [ $? -eq 0 ] ; then
		echo "Opening SSH connection on new session: localhost:$LOCAL_PORT"
		echo "$PID >$PORT_CACHE_FILE.smp-pid"
		echo $PID >$PORT_PID_CACHE_FILE
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
		rm -f $PORT_CACHE_FILE
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

