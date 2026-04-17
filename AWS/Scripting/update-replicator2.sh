export REPLICATOR_ARN=arn:aws:kafka:us-east-1:011935884485:replicator/msk2-to-msk1-radar-replicator/996187f3-2831-45dc-a072-35ebfb0e9f95-4
export MSK1_ARN="arn:aws:kafka:us-east-1:011935884485:cluster/nws-dl-msk-1/751c301b-b22d-46a4-ba79-2413bd2fe797-22"
export MSK2_ARN="arn:aws:kafka:us-east-1:011935884485:cluster/nws-dl-msk-2/3faeee30-bcc7-4a49-87e4-c8dcf9afcc3d-22"

CURRENT_VERSION=$(aws kafka describe-replicator --replicator-arn "$REPLICATOR_ARN" \
  --query 'CurrentVersion' --output text)
echo "Current Version: $CURRENT_VERSION"

aws kafka update-replication-info \
  --replicator-arn "$REPLICATOR_ARN" \
  --current-version "$CURRENT_VERSION" \
  --source-kafka-cluster-arn "$MSK2_ARN" \
  --target-kafka-cluster-arn "$MSK1_ARN" \
  --topic-replication file://topic-replication.json --debug
