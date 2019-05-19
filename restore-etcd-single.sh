#!/bin/bash
#checks for later
#exists? /opt/rke/etcd /var/lib/etcd
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`
if [ -d "/opt/rke/etcd" ]
then
        echo ${green}/opt/rke/etcd exists, please move this directory out of the way and re-run the script${reset}
        exit 1
fi
if [ ! -d "/var/lib/etcd" ]
then
        echo "${green}/var/lib/etcd doesn't exist, script has not accounted for this, exiting${reset}"
        exit 1
fi
if [ ! -f "/etc/kubernetes/snapshot.db" ]
then
        echo "${green}/etc/kubernetes/snapshot.db does not exist, please place your snapshot here to have it restored.  Future versions will have options to handle this better${reset}"
        exit 1
fi
if [ ! "$(docker ps -a --filter "name=^/etcd$" --format '{{.Names}}')" == "etcd" ]
then
        echo "${green} etcd container does not exist, script cannot proceed${reset}"
        exit 1
fi
if [ "$(docker ps -a --filter "name=^/etcd-restore$" --format '{{.Names}}')" == "etcd-restore" ]
then
        echo "${green} etcd-restore container exists, please remove this container before running the script${reset}"
        exit 1
fi
if [ "$(docker ps -a --filter "name=^/etcd-reinit$" --format '{{.Names}}')" == "etcd-reinit" ]
then
        echo "${green} etcd-reinit container exists, please remove this container before running the script${reset}"
        exit 1
fi
#ADD CHECK FOR runlike image later.

#container exists? etcd-restore etcd-reinit etcd
RUNLIKE=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock assaflavie/runlike etcd)
echo ${red}Setting etcd restart policy to never restart \(no\)${reset}
docker update --restart=no etcd
ETCD_BACKUP_TIME=$(date +%Y-%m-%d--%H%M%S)
echo ${red}Renaming original etcd container to etcd-old--${ETCD_BACKUP_TIME}
docker rename etcd etcd-old--${ETCD_BACKUP_TIME}
echo ${red}Stopping original etcd container
docker stop etcd-old--${ETCD_BACKUP_TIME}
echo ${red}Moving old etcd data directory /var/lib/etcd to /var/lib/etcd-old--${ETCD_BACKUP_TIME}${reset}
mv /var/lib/etcd /var/lib/etcd-old--${ETCD_BACKUP_TIME}

ETCD_HOSTNAME=$(sed  's,^.*--hostname=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
ETCDCTL_ENDPOINT="https://0.0.0.0:2379"
ETCDCTL_CACERT=$(sed  's,^.*ETCDCTL_CACERT=\([^"]*\).*,\1,g' <<< $RUNLIKE)
ETCDCTL_CERT=$(sed  's,^.*ETCDCTL_CERT=\([^"]*\).*,\1,g' <<< $RUNLIKE)
ETCDCTL_KEY=$(sed  's,^.*ETCDCTL_KEY=\([^"]*\).*,\1,g' <<< $RUNLIKE)
ETCD_VERSION=$(sed  's,^.*rancher/coreos-etcd:\([^ ]*\).*,\1,g' <<< $RUNLIKE)
INITIAL_ADVERTISE_PEER_URL=$(sed  's,^.*initial-advertise-peer-urls=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
ETCD_NAME=$(sed  's,^.*name=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
INITIAL_CLUSTER=$(sed  's,^.*--initial-cluster=\('"$ETCD_NAME"'\)=\([^,]*\).*,\1=\2,g' <<< $RUNLIKE)
ETCD_SNAPSHOT_LOCATION='/etc/kubernetes/snapshot.db'

RESTORE_RUNLIKE='docker run
--name=etcd-restore
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
-ti rancher/coreos-etcd:'$ETCD_VERSION' /usr/local/bin/etcdctl snapshot restore '$ETCD_SNAPSHOT_LOCATION'
--initial-advertise-peer-urls='$INITIAL_ADVERTISE_PEER_URL'
--initial-cluster='$INITIAL_CLUSTER'
--initial-cluster-token=etcd-cluster-1
--data-dir=/opt/rke/etcd
--name='$ETCD_NAME''

#RESTORE ETCD
echo ${red}Restoring etcd snapshot${reset}
eval $RESTORE_RUNLIKE
echo ${green}Sleeping for 10 seconds so etcd can do its restore${reset}
sleep 10

echo ${red}Stopping etcd-restore container${reset}
docker stop etcd-restore

echo ${red}Moving restored etcd directory in place{$reset}
mv /opt/rke/etcd /var/lib/

echo ${red}Deleting etcd-restore container${reset}
docker rm -f etcd-restore

#INITIALIZE NEW RUNLIKE
NEW_RUNLIKE=$RUNLIKE

#ADD --force-new-cluster
NEW_RUNLIKE=$(sed  's,^\(.*'$ETCD_VERSION' \)\([^ ]*\)\(.*\),\1\2 --force-new-cluster\3,g' <<< $NEW_RUNLIKE)

#REMOVE OTHER ETCD NODES FROM --initial-cluster
ORIG_INITIAL_CLUSTER=$(sed  's,^.*initial-cluster=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
NEW_RUNLIKE=$(sed  's`'"$ORIG_INITIAL_CLUSTER"'`'"$INITIAL_CLUSTER"'`g' <<< $NEW_RUNLIKE)

#CHANGE NAME TO etcd-reinit
NEW_RUNLIKE=$(sed  's`'--name=etcd'`'--name=etcd-reinit'`g' <<< $NEW_RUNLIKE)

#REINIT ETCD
echo ${red}Running etcd-reinit${reset}
eval $NEW_RUNLIKE
echo ${green}Sleeping for 20 seconds so etcd can do reinit things${reset}
sleep 20

#echo ${green}Tailing last 40 lines of etcd-reinit${reset}
#docker logs etcd-reinit --tail 40

#STOP AND REMOVE etcd-reinit
echo ${red}Stopping and removing etcd-reinit${reset}
docker stop etcd-reinit
docker rm -f etcd-reinit

#CHANGE NAME BACK TO etcd
NEW_RUNLIKE=$(sed  's`'--name=etcd-reinit'`'--name=etcd'`g' <<< $NEW_RUNLIKE)

#REMOVE --force-new-cluster
NEW_RUNLIKE=$(sed  's`--force-new-cluster ``g' <<< $NEW_RUNLIKE)

#FINALLY RUN NEW SHINY RESTORED ETCD
echo ${red}Launching shiny new etcd${reset}
eval $NEW_RUNLIKE

echo ${red}Restarting kubelet and kube-apiserver if they exist${reset}
docker restart kubelet kube-apiserver
