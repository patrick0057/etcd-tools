#!/bin/bash
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

RUNLIKE=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock assaflavie/runlike etcd)
ETCD_NAME=$(sed  's,^.*name=\([^ ]*\).*,\1,g' <<< $RUNLIKE)

#GET ALL ENVIRONMENT VARIABLES ON HOST
export $(docker inspect etcd -f '{{.Config.Env}}'| sed 's/[][]//g')
ETCD_VER=$(sed  's,^.*rancher/coreos-etcd:\([^-]*\).*,\1,g' <<< $RUNLIKE)
# choose either URL
GOOGLE_URL=https://storage.googleapis.com/etcd
GITHUB_URL=https://github.com/etcd-io/etcd/releases/download
DOWNLOAD_URL=${GOOGLE_URL}

rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
rm -rf /tmp/etcd-download-test && mkdir -p /tmp/etcd-download-test

curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
tar xzvf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd-download-test --strip-components=1
rm -f /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz

/tmp/etcd-download-test/etcd --version
ETCDCTL_API=3 /tmp/etcd-download-test/etcdctl version

echo ${red}Setting etcd restart policy to never restart \(no\)${reset}
docker update --restart=no etcd
ETCD_BACKUP_TIME=$(date +%Y-%m-%d--%H%M%S)
echo ${red}Stopping etcd container${reset}
docker stop etcd
echo ${green}Waiting 20 seconds for etcd to stop${reset}
sleep 20
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
INITIAL_CLUSTER=$(sed  's,^.*--initial-cluster=.*\('"$ETCD_NAME"'\)=\([^,^ ]*\).*,\1=\2,g' <<< $RUNLIKE)
INITIAL_CLUSTER_TOKEN=$(sed  's,^.*initial-cluster-token=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
ADVERTISE_CLIENT_URLS=$(sed  's,^.*advertise-client-urls=\([^ ]*\).*,\1,g' <<< $RUNLIKE)
etcd \
--peer-client-cert-auth \
--client-cert-auth \
--initial-cluster=etcd-3.17.156.241=https://3.17.156.241:2380,etcd-3.16.76.101=https://3.16.76.101:2380,etcd-18.191.139.66=https://18.191.139.66:2380 \
--initial-cluster-state=existing \
--trusted-ca-file=${ETCDCTL_CACERT} \
--listen-client-urls=https://0.0.0.0:2379 \
--initial-advertise-peer-urls=${INITIAL_ADVERTISE_PEER_URL} \
--listen-peer-urls=https://0.0.0.0:2380 \
--heartbeat-interval=500 \
--election-timeout=5000 \
--data-dir=/var/lib/etcd/ \
--initial-cluster-token=${INITIAL_CLUSTER_TOKEN} \
--peer-cert-file=${ETCDCTL_CERT} \
--peer-key-file=${ETCDCTL_KEY} \
--name=${ETCD_NAME} \
--advertise-client-urls=${ADVERTISE_CLIENT_URLS} \
--peer-trusted-ca-file=${ETCDCTL_CACERT} \
--cert-file=${ETCDCTL_CERT} \
--key-file=${ETCDCTL_KEY}

          exec etcd --name ${HOSTNAME} \
              --initial-advertise-peer-urls https://${HOSTNAME}.${SET_NAME}.${CLUSTER_NAMESPACE}:2380 \
              --listen-peer-urls https://0.0.0.0:2380 \
              --listen-client-urls http://0.0.0.0:2379 \
              --advertise-client-urls http://${HOSTNAME}.${SET_NAME}.${CLUSTER_NAMESPACE}:2379 \
              --initial-cluster-token etcd-cluster-1 \
              --data-dir /var/run/etcd/default.etcd \
              --initial-cluster $(initial_peers) \
              --initial-cluster-state new \
              --peer-client-cert-auth \
              --peer-trusted-ca-file=/etcd-certs/ca.pem \
              --peer-cert-file=/etcd-certs/etcd.pem \
              --peer-key-file=/etcd-certs/etcd-key.pem

ETCDCTL_API=3 etcdctl --cacert $ETCDCTL_CACERT --cert $ETCDCTL_CERT --key ${ETCDCTL_KEY} member add ${ETCD_NAME} --peer-urls=${INITIAL_ADVERTISE_PEER_URL}
curl -k --cacert $ETCDCTL_CACERT --cert $ETCDCTL_CERT --key ${ETCDCTL_KEY} https://18.191.139.66:2379/v2/members -XPOST -H "Content-Type: application/json" -d '{"peerURLs":["${INITIAL_ADVERTISE_PEER_URL}
