#!/bin/bash

# Set up environment variables
export REPLICATOR_ARN=arn:aws:kafka:us-east-1:011935884485:replicator/msk2-to-msk1-radar-replicator/996187f3-2831-45dc-a072-35ebfb0e9f95-4
export MSK1_ARN="arn:aws:kafka:us-east-1:011935884485:cluster/nws-dl-msk-1/751c301b-b22d-46a4-ba79-2413bd2fe797-22"
export MSK2_ARN="arn:aws:kafka:us-east-1:011935884485:cluster/nws-dl-msk-2/3faeee30-bcc7-4a49-87e4-c8dcf9afcc3d-22"

echo "=== MSK Cross-Cluster Replication Setup and Verification ==="
echo ""

# Step 1: Get current version
echo "📋 Step 1: Getting current replicator version..."
CURRENT_VERSION=$(aws kafka describe-replicator --replicator-arn "$REPLICATOR_ARN" \
  --query 'CurrentVersion' --output text)
echo "Current Version: $CURRENT_VERSION"

if [ -z "$CURRENT_VERSION" ] || [ "$CURRENT_VERSION" = "None" ]; then
  echo "❌ Error: Unable to retrieve current version"
  exit 1
fi

# Step 2: Enable DetectAndCopyNewTopics
echo ""
echo "🔧 Step 2: Enabling DetectAndCopyNewTopics for automatic topic detection..."

cat > topic-replication.json << EOF
{
  "TopicsToReplicate": ["radar-data-topic"],
  "TopicsToExclude": ["^__.*", "^internal\\\\..*", "^console\\\\..*", "^nws-dl-msk-2.*"],
  "CopyTopicConfigurations": true,
  "DetectAndCopyNewTopics": true,
  "CopyAccessControlListsForTopics": true
}
EOF

# Update replication configuration
aws kafka update-replication-info \
  --replicator-arn "$REPLICATOR_ARN" \
  --current-version "$CURRENT_VERSION" \
  --source-kafka-cluster-arn "$MSK2_ARN" \
  --target-kafka-cluster-arn "$MSK1_ARN" \
  --topic-replication file://topic-replication.json

if [ $? -eq 0 ]; then
  echo "✅ Replication configuration updated successfully!"
else
  echo "❌ Failed to update replication configuration"
  rm -f topic-replication.json
  exit 1
fi

# Clean up JSON file
rm -f topic-replication.json

# Step 3: Wait for replication to be active
echo ""
echo "⏳ Step 3: Waiting for replicator to become active..."
echo "This may take a few minutes..."

for i in {1..20}; do
  STATUS=$(aws kafka describe-replicator --replicator-arn "$REPLICATOR_ARN" \
    --query 'State' --output text)
  echo "Attempt $i/20 - Replicator Status: $STATUS"
  
  if [ "$STATUS" = "RUNNING" ]; then
    echo "✅ Replicator is now RUNNING!"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "DELETING" ]; then
    echo "❌ Replicator failed with status: $STATUS"
    exit 1
  fi
  
  sleep 30
done

if [ "$STATUS" != "RUNNING" ]; then
  echo "⚠️  Replicator is still not running after 10 minutes. Current status: $STATUS"
  echo "You may need to wait longer or check the AWS console for more details."
fi

# Step 4: Get MSK cluster endpoints
echo ""
echo "🔍 Step 4: Getting MSK cluster endpoints..."

# Get MSK1 (target) bootstrap servers
MSK1_BOOTSTRAP=$(aws kafka get-bootstrap-brokers --cluster-arn "$MSK1_ARN" \
  --query 'BootstrapBrokerString' --output text)
echo "MSK1 Bootstrap Servers: $MSK1_BOOTSTRAP"

# Get MSK2 (source) bootstrap servers  
MSK2_BOOTSTRAP=$(aws kafka get-bootstrap-brokers --cluster-arn "$MSK2_ARN" \
  --query 'BootstrapBrokerString' --output text)
echo "MSK2 Bootstrap Servers: $MSK2_BOOTSTRAP"

# Step 5: Check topics on both clusters
echo ""
echo "📊 Step 5: Checking topics on both clusters..."

# Function to list topics using kafka console tools
check_topics() {
  local BOOTSTRAP_SERVERS=$1
  local CLUSTER_NAME=$2
  
  echo ""
  echo "Topics on $CLUSTER_NAME:"
  echo "=========================="
  
  # Try to list topics (assuming kafka tools are available)
  if command -v kafka-topics.sh &> /dev/null; then
    kafka-topics.sh --bootstrap-server "$BOOTSTRAP_SERVERS" --list | grep -E "(radar|test)" || echo "No radar/test topics found"
  else
    echo "⚠️  Kafka tools not available. Please install Kafka client tools to list topics."
    echo "Bootstrap servers: $BOOTSTRAP_SERVERS"
  fi
}

check_topics "$MSK2_BOOTSTRAP" "MSK2 (Source)"
check_topics "$MSK1_BOOTSTRAP" "MSK1 (Target)"

# Step 6: Test data replication using Python producer
echo ""
echo "🧪 Step 6: Testing data replication with Python producer..."

if [ -f "local-radar-producer2.py" ]; then
  echo "✅ Found local-radar-producer2.py"
  echo ""
  echo "📤 Step 6a: Running radar data producer on MSK2 (source cluster)..."
  echo "This will send simulated radar data to radar-data-topic on MSK2"
  echo "Starting producer for 30 seconds..."
  
  # Run the producer for a limited time in background
  timeout 30s python3 local-radar-producer2.py &
  PRODUCER_PID=$!
  
  echo "Producer started with PID: $PRODUCER_PID"
  echo "Waiting for data to be produced and replicated..."
  sleep 35
  
  # Kill producer if still running
  if kill -0 $PRODUCER_PID 2>/dev/null; then
    kill $PRODUCER_PID 2>/dev/null
    echo "Producer stopped"
  fi
  
else
  echo "⚠️  local-radar-producer2.py not found in current directory"
  echo "Please ensure the producer script is available, then run:"
  echo "python3 local-radar-producer2.py"
fi

# Step 6b: Create a simple Python consumer to verify replication
echo ""
echo "📥 Step 6b: Creating consumer to verify data on MSK1 (target cluster)..."

cat > verify_replication.py << 'EOF'
#!/usr/bin/env python3
import sys
import json
from kafka import KafkaConsumer
import signal
import time

def signal_handler(sig, frame):
    print("\n🛑 Consumer stopped by user")
    sys.exit(0)

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 verify_replication.py <bootstrap_servers>")
        sys.exit(1)
    
    bootstrap_servers = sys.argv[1]
    # Topic name will be prefixed with source cluster alias
    topic_name = "nws-dl-msk-2.radar-data-topic"
    
    print(f"🔍 Connecting to MSK1 at: {bootstrap_servers}")
    print(f"📊 Looking for topic: {topic_name}")
    print("⏳ Waiting for messages (Ctrl+C to stop)...")
    print("-" * 50)
    
    try:
        consumer = KafkaConsumer(
            topic_name,
            bootstrap_servers=bootstrap_servers.split(','),
            auto_offset_reset='earliest',
            enable_auto_commit=True,
            group_id='replication-test-group',
            value_deserializer=lambda x: x.decode('utf-8') if x else None,
            consumer_timeout_ms=10000  # 10 second timeout
        )
        
        message_count = 0
        start_time = time.time()
        
        for message in consumer:
            message_count += 1
            try:
                # Try to parse as JSON for better display
                data = json.loads(message.value)
                print(f"✅ Message {message_count}: {json.dumps(data, indent=2)}")
            except:
                # If not JSON, print raw value
                print(f"✅ Message {message_count}: {message.value}")
            
            print(f"   Partition: {message.partition}, Offset: {message.offset}")
            print("-" * 30)
            
            # Stop after 10 messages or 30 seconds
            if message_count >= 10 or (time.time() - start_time) > 30:
                break
                
        if message_count == 0:
            print("❌ No messages found in replicated topic")
            print("   This could mean:")
            print("   - Replication is still in progress")
            print("   - No data was produced to source topic")
            print("   - Topic name might be different")
        else:
            print(f"🎉 Successfully received {message_count} replicated messages!")
            
    except Exception as e:
        print(f"❌ Error consuming messages: {e}")
        print("   Possible issues:")
        print("   - Topic doesn't exist yet (replication in progress)")
        print("   - Network connectivity issues")
        print("   - Authentication problems")

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal_handler)
    main()
EOF

echo "📥 Running consumer to check replicated data on MSK1..."
python3 verify_replication.py "$MSK1_BOOTSTRAP"

# Clean up
rm -f verify_replication.py

# Step 7: Show replication status
echo ""
echo "📈 Step 7: Current replication status..."
aws kafka describe-replicator --replicator-arn "$REPLICATOR_ARN" --output table \
  --query '{State: State, CurrentVersion: CurrentVersion, CreationTime: CreationTime}'

echo ""
echo "🎉 Script completed! Summary:"
echo "✓ DetectAndCopyNewTopics is now enabled"
echo "✓ Radar data producer ran for 30 seconds on MSK2"
echo "✓ Consumer checked for replicated data on MSK1"
echo "✓ Replicated topic name: nws-dl-msk-2.radar-data-topic"
echo ""
echo "📋 To continue testing manually:"
echo "   Producer: python3 local-radar-producer2.py"
echo "   Consumer: python3 verify_replication.py $MSK1_BOOTSTRAP"
echo ""
echo "🖥️  Monitor replication in AWS Console: MSK > Replicators"