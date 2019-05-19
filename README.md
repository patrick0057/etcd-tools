# etcd-tools
This is a collection of etcd tool to do long and tedious tasks.  Currnetly there is a restore tool for restoring a snapshot to a single node and a join tool for rejoining other members after the restore has been completed on the single node.

1. Take an etcd snapshot before starting using one of the following commands (only one will work):
```bash
docker exec etcd etcdctl snapshot save /tmp/snapshot.db && docker cp etcd:/tmp/snapshot.db .
```
```bash
docker exec etcd sh -c "etcdctl snapshot --endpoints=\$ETCDCTL_ENDPOINT save /tmp/snapshot.db" && docker cp etcd:/tmp/snapshot.db .
```

2. Stop etcd on all nodes except for the one you are restoring:
```bash
docker update --restart=no etcd && docker stop etcd
```

3. Run the restore:
```bash
./restore-etcd-single.sh </path/to/snapshot>
```

4. Rejoin etcd nodes by running the following command.  SSH key is option if you have a default one already set on your ssh account.
```bash
./etcd-join.sh <ssh user> <remote etcd IP> [path to ssh key for remote box]
```
5. Restart kubelet and kube-apiserver on all servers where it has not been restarted for you by the script already.
```bash
docker restart kubelet kube-apiserver
```

