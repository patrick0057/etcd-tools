# etcd-tools
take an etcd snapshot before starting using one of the following commands.
```bash
docker exec etcd etcdctl snapshot save /tmp/snapshot.db && docker cp etcd:/tmp/snapshot.db .
```
```bash
docker exec etcd sh -c "etcdctl snapshot --endpoints=\$ETCDCTL_ENDPOINT save /tmp/snapshot.db" && docker cp etcd:/tmp/snapshot.db .
```

stop etcd on all nodes except for the one you are restoring
```bash
docker update --restart=no etcd && docker stop etcd
```

