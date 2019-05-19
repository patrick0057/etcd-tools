#!/bin/bash
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`
USAGE='Usage: ./etcd-join.sh <ssh user> <remote etcd IP> [path to ssh key for remote box]'
rootcmd () {
    if [[ $EUID -ne 0 ]]; then
   echo "${green}Running as non root user, issuing command with sudo.${reset}" 
   sudo $1
    else 
     $1
fi
}
if [[ $1 == '' ]] || [[ $2 == '' ]] || [[ $@ =~ " -h" ]] || [[ $@ =~ " --help" ]]
 then
 echo "${green}${USAGE}${reset}"
 exit 1
fi
if [ "$(docker ps -a --filter "name=^/etcd-join$" --format '{{.Names}}')" == "etcd-join" ]
then
    docker rm -f etcd-join
fi
REMOTE_SSH_USER=$1
REMOTE_SSH_IP=$2
REMOTE_SSH_KEY=$3
echo ${green}Verifying SSH connections...${reset}
echo ssh user: ${REMOTE_SSH_USER}
echo ssh ip: ${REMOTE_SSH_IP}
echo ssh key: ${REMOTE_SSH_KEY}
#echo length ${#REMOTE_SSH_KEY}
if [[ ${#REMOTE_SSH_KEY} == 0 ]]
then
    ssh -o StrictHostKeyChecking=no -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP exit
    if [[ $? -ne 0 ]]
    then
        echo ${green}Unable to connect to remote SSH host, aborting script!  Did you set your ssh key\?${reset}
        echo
        echo "${green}${USAGE}${reset}"
        exit 1
        
    fi
    else 
        ssh -o StrictHostKeyChecking=no -i ${REMOTE_SSH_KEY} -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP exit
        if [[ $? -ne 0 ]]
        then
            echo ${green}Unable to connect to remote SSH host, aborting script!${reset}
            echo
            echo "${green}${USAGE}${reset}"
            exit 1
        fi
fi
echo ${green}SSH test succesful.${reset}
echo
sshcmd () {
if [[ ${#REMOTE_SSH_KEY} == 0 ]]
then
    ssh -o StrictHostKeyChecking=no -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP $1
    else
    ssh -o StrictHostKeyChecking=no -i ${REMOTE_SSH_KEY} -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP $1
fi
}
export $(docker inspect etcd -f '{{.Config.Env}}'| sed 's/[][]//g')
docker inspect etcd &> /dev/null
if [[ $? -ne 0 ]]
then
 echo ${green}Uable to inspect the etcd container, does it still exist?  Aborting script!${reset}
 echo
 echo "${green}${USAGE}${reset}"
 exit 1
fi
echo ${green}I was able to inspect the etcd container!  Script will proceed...${reset}
echo


echo ${green}Gathering information about your etcd container${reset}
RUNLIKE=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock assaflavie/runlike etcd)



#GET ALL ENVIRONMENT VARIABLES ON HOST

#export $(docker inspect etcd -f '{{.Config.Env}}'| sed 's/[][]//g')
#ETCD_VER=$(sed  's,^.*rancher/coreos-etcd:\([^-]*\).*,\1,g' <<< $RUNLIKE)

# choose either URL
#GOOGLE_URL=https://storage.googleapis.com/etcd
#GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
#DOWNLOAD_URL=${GOOGLE_URL}

#rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
#rm -rf /tmp/etcd-download-test && mkdir -p /tmp/etcd-download-test

#curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
#tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1
#rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

#/tmp/etcd-download-test/etcd --version
#ETCDCTL_API=3 /tmp/etcd-download-test/etcdctl version

echo ${red}Setting etcd restart policy to never restart \"no\"${reset}
docker update --restart=no etcd

ETCD_BACKUP_TIME=$(date +%Y-%m-%d--%H%M%S)

echo ${red}Stopping etcd container${reset}
docker stop etcd
echo ${green}Waiting 11 seconds for etcd to stop${reset}
sleep 11
echo ${red}Moving old etcd data directory /var/lib/etcd to /var/lib/etcd-old--${ETCD_BACKUP_TIME}${reset}
rootcmd "mv /var/lib/etcd /var/lib/etcd-old--${ETCD_BACKUP_TIME}"

#ls -lash /var/lib/etcd
sleep 2
ETCD_NAME=$(sed  's,^.*name=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
ETCD_HOSTNAME=$(sed  's,^.*--hostname=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
ETCDCTL_ENDPOINT="https://0.0.0.0:2379"
ETCDCTL_CACERT=$(sed  's,^.*ETCDCTL_CACERT=\([^"]*\).*,\1,g' <<< $RUNLIKE)
ETCDCTL_CERT=$(sed  's,^.*ETCDCTL_CERT=\([^"]*\).*,\1,g' <<< $RUNLIKE)
ETCDCTL_KEY=$(sed  's,^.*ETCDCTL_KEY=\([^"]*\).*,\1,g' <<< $RUNLIKE)
ETCD_VERSION=$(sed  's,^.*rancher/coreos-etcd:\([^ ]*\).*,\1,g' <<< $RUNLIKE)
INITIAL_ADVERTISE_PEER_URL=$(sed  's,^.*initial-advertise-peer-urls=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
ETCD_NAME=$(sed  's,^.*name=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
INITIAL_CLUSTER=$(sed  's,^.*--initial-cluster=.*\('"$ETCD_NAME"'\)=\([^,^ ]*\).*,\1=\2,g' <<< $RUNLIKE)
INITIAL_CLUSTER_TOKEN=$(sed  's,^.*initial-cluster-token=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
ADVERTISE_CLIENT_URLS=$(sed  's,^.*advertise-client-urls=\([^ ]*\).*,\1,g' <<< $RUNLIKE)

#CHECK IF WE NEED TO ADD --endpoints TO THE COMMAND
REQUIRE_ENDPOINT=$(sshcmd "docker exec etcd netstat -lpna | grep \:2379 | grep tcp | grep LISTEN | tr -s ' ' | cut -d' ' -f4")
if [[ $REQUIRE_ENDPOINT =~ ":::" ]]
then
    echo "${green} etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints${reset}"
    ETCD_ADD_MEMBER_CMD="etcdctl --cacert $ETCDCTL_CACERT --cert $ETCDCTL_CERT --key ${ETCDCTL_KEY} member add ${ETCD_NAME} --peer-urls=${INITIAL_ADVERTISE_PEER_URL}"
    else
        echo "${green} etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints${reset}"
        ETCD_ADD_MEMBER_CMD="etcdctl --cacert $ETCDCTL_CACERT --cert $ETCDCTL_CERT --key ${ETCDCTL_KEY} member --endpoints ${REQUIRE_ENDPOINT} add ${ETCD_NAME} --peer-urls=${INITIAL_ADVERTISE_PEER_URL}"
fi

echo ${red}Connecting to remote etcd and issuing add member command${reset}
export $(sshcmd "docker exec etcd ${ETCD_ADD_MEMBER_CMD} | grep ETCD_INITIAL_CLUSTER")
echo "${red}ETCD_ADD_MEMBER_CMD has been set to ${ETCD_ADD_MEMBER_CMD} <-If this is blank etcd-join will fail${reset}"


RESTORE_RUNLIKE='docker run
--name=etcd-join
--hostname='$ETCD_HOSTNAME'
--env="ETCDCTL_API=3"
--env="ETCDCTL_ENDPOINT='$ETCDCTL_ENDPOINT'"
--env="ETCDCTL_CACERT='$ETCDCTL_CACERT'"
--env="ETCDCTL_CERT='$ETCDCTL_CERT'"
--env="ETCDCTL_KEY='$ETCDCTL_KEY'"
--env="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
--volume="/var/lib/etcd:/var/lib/rancher/etcd/:z"
--volume="/etc/kubernetes:/etc/kubernetes:z"
--volume="/opt/rke:/opt/rke:z"
--network=host
--label io.rancher.rke.container.name="etcd"
--detach=true rancher/coreos-etcd:'$ETCD_VERSION' /usr/local/bin/etcd
--peer-client-cert-auth
--client-cert-auth
--initial-cluster='${ETCD_INITIAL_CLUSTER}'
--initial-cluster-state=existing
--trusted-ca-file='${ETCDCTL_CACERT}'
--listen-client-urls=https://0.0.0.0:2379
--initial-advertise-peer-urls='${INITIAL_ADVERTISE_PEER_URL}'
--listen-peer-urls=https://0.0.0.0:2380
--heartbeat-interval=500
--election-timeout=5000
--data-dir=/var/lib/rancher/etcd/
--initial-cluster-token='${INITIAL_CLUSTER_TOKEN}'
--peer-cert-file='${ETCDCTL_CERT}'
--peer-key-file='${ETCDCTL_KEY}'
--name='${ETCD_NAME}'
--advertise-client-urls='${ADVERTISE_CLIENT_URLS}'
--peer-trusted-ca-file='${ETCDCTL_CACERT}'
--cert-file='${ETCDCTL_CERT}'
--key-file='${ETCDCTL_KEY}''
echo ${green}Running the following command:${reset}
echo $RESTORE_RUNLIKE




echo ${green}Launching etcd-join${reset}
eval $RESTORE_RUNLIKE
echo


#etcd \
#--peer-client-cert-auth
#--client-cert-auth
#--initial-cluster=${INITIAL_CLUSTER}
#--initial-cluster-state=existing
#--trusted-ca-file=${ETCDCTL_CACERT}
#--listen-client-urls=https://0.0.0.0:2379
#--initial-advertise-peer-urls=${INITIAL_ADVERTISE_PEER_URL}
#--listen-peer-urls=https://0.0.0.0:2380
#--heartbeat-interval=500
#--election-timeout=5000
#--data-dir=/var/lib/rancher/etcd/
#--initial-cluster-token=${INITIAL_CLUSTER_TOKEN}
#--peer-cert-file=${ETCDCTL_CERT}
#--peer-key-file=${ETCDCTL_KEY}
#--name=${ETCD_NAME}
#--advertise-client-urls=${ADVERTISE_CLIENT_URLS}
#--peer-trusted-ca-file=${ETCDCTL_CACERT}
#--cert-file=${ETCDCTL_CERT}
#--key-file=${ETCDCTL_KEY}

echo ${green}Script sleeping for 10 seconds${reset}
sleep 10

if [ ! "$(docker ps --filter "name=^/etcd-join$" --format '{{.Names}}')" == "etcd-join" ]
then
        echo "${green} etcd-join is not running, something went wrong.  Make sure the etcd cluster only has healthy and online members then try again.${reset}"
        exit 1
fi

echo ${green}etcd-join appears to be running still, this is a good sign.  Proceeding with cleanup.${reset}
echo ${red}Stopping etcd-join${reset}
docker stop etcd-join
echo ${red}Deleting etcd-join${reset}
docker rm etcd-join
echo ${red}Starting etcd${reset}
docker start etcd

if [ ! "$(docker ps --filter "name=^/etcd$" --format '{{.Names}}')" == "etcd" ]
then
        echo "${green} etcd is not running, something went wrong.${reset}"
        exit 1
fi
echo "${green}etcd is running, checking etcd things before exitting.${reset}"
if [[ $REQUIRE_ENDPOINT =~ ":::" ]]
then
    echo "${green} etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints${reset}"
    sshcmd "docker exec etcd etcdctl member list"
    else
        echo "${green} etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints${reset}"
        sshcmd "docker exec etcd etcdctl --endpoints ${REQUIRE_ENDPOINT} member list"
fi

#curl -k --cacert $ETCDCTL_CACERT --cert $ETCDCTL_CERT --key ${ETCDCTL_KEY} https://18.191.139.66:2379/v3beta/cluster/member/add -XPOST -H "Content-Type: application/json" -d '{"peerURLs":["${INITIAL_ADVERTISE_PEER_URL}"]}'

echo ${red}Setting etcd restart policy to always restart${reset}
docker update --restart=always etcd

echo ${red}Restarting kubelet and kube-apiserver if they exist${reset}
docker restart kubelet kube-apiserver
