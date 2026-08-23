#!/bin/bash

echo 'waiting configSrv...'
until mongosh --host configSrv:27017 --eval 'db.adminCommand("ping")' | grep 'ok'; do sleep 2; done
mongosh --host configSrv:27017 --eval '
  rs.initiate({
    _id: "config_server",
    configsvr: true,
    members: [{ _id: 0, host: "configSrv:27017" }]
  })
'

echo 'waiting shard1 nodes...'
until mongosh --host shard1-1:27018 --eval 'db.adminCommand("ping")' | grep 'ok'; do sleep 2; done

echo 'Initializing Shard 1 Replica Set (3 nodes)...'
mongosh --host shard1-1:27018 --eval '
  rs.initiate({
    _id: "shard1",
    members: [
      { _id: 0, host: "shard1-1:27018" },
      { _id: 1, host: "shard1-2:27018" },
      { _id: 2, host: "shard1-3:27018" }
    ]
  })
'

echo 'waiting shard2 nodes...'
until mongosh --host shard2-1:27019 --eval 'db.adminCommand("ping")' | grep 'ok'; do sleep 2; done

echo 'Initializing Shard 2 Replica Set (3 nodes)...'
mongosh --host shard2-1:27019 --eval '
  rs.initiate({
    _id: "shard2",
    members: [
      { _id: 0, host: "shard2-1:27019" },
      { _id: 1, host: "shard2-2:27019" },
      { _id: 2, host: "shard2-3:27019" }
    ]
  })
'

echo 'waiting for primary elections in shard replica sets...'
sleep 15

echo 'waiting router...'
until mongosh --host mongos_router:27020 --eval 'db.adminCommand("ping")' | grep 'ok'; do sleep 2; done

echo 'Adding Sharded Replica Sets to cluster via mongos...'
mongosh --host mongos_router:27020 --eval '
  sh.addShard("shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
  sh.addShard("shard2/shard2-1:27019,shard2-2:27019,shard2-3:27019");
  
  sh.enableSharding("somedb");
  db = db.getSiblingDB("somedb");
  sh.shardCollection("somedb.helloDoc", { "_id": "hashed" });
'

echo 'Generating 1500 test documents in somedb.helloDoc...'
mongosh --host mongos_router:27020 --eval '
  db = db.getSiblingDB("somedb");
  var docs = [];
  for (var i = 1; i <= 1500; i++) {
    docs.push({ name: "accessory_" + i, type: "case", status: "active" });
  }
  db.helloDoc.insertMany(docs);
  print("Total docs inserted: " + db.helloDoc.countDocuments());
'

echo 'Cluster configuration with replication and data seeding complete.'
