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

echo 'waiting shard1...'
until mongosh --host shard1:27018 --eval 'db.adminCommand("ping")' | grep 'ok'; do sleep 2; done
mongosh --host shard1:27018 --eval '
  rs.initiate({
    _id: "shard1",
    members: [{ _id: 0, host: "shard1:27018" }]
  })
'

echo 'waiting shard2...'
until mongosh --host shard2:27019 --eval 'db.adminCommand("ping")' | grep 'ok'; do sleep 2; done
mongosh --host shard2:27019 --eval '
  rs.initiate({
    _id: "shard2",
    members: [{ _id: 0, host: "shard2:27019" }]
  })
'

# Даем шардам 5 секунд, чтобы они успели выбрать Primary узлы внутри себя после rs.initiate
echo 'waiting for primary elections...'
sleep 5

echo 'waiting router...'
until mongosh --host mongos_router:27020 --eval 'db.adminCommand("ping")' | grep 'ok'; do sleep 2; done

mongosh --host mongos_router:27020 --eval '
  sh.addShard("shard1/shard1:27018");
  sh.addShard("shard2/shard2:27019");
  sh.enableSharding("somedb");
  
  db = db.getSiblingDB("somedb");
  sh.shardCollection("somedb.helloDoc", { "_id": "hashed" });
'

# Автоматическое наполнение базы 1500 документами
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

echo 'Cluster configuration and data seeding complete.'