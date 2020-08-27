import boto3
conn = boto3.client('ec2')
response = conn.create_security_group(
    GroupName='mywebgroup', Description='Test')
print(response)
keypair = conn.create_keypair(KeyName='webkey')
print(keypair['KeyMaterial'])
ec2_conn = boto3.client('ec2')
instance = ec2_conn.create_instance(ImageId='ami-oiitest0825', MinCount=1, MaxCount=1,
                                    SecurityGroup=['mywebgroup'], KeyName='webkey', InstanceType='t2.micro')
print(instance)
ids = []
instances = ec2_conn.instance.filter(Filters=[('Name':'instance-state-name', 'Values':['running'])])
for instance in instances:
    ids.append(instance.id)
    print(instance.name, instance.instance_type)
ec2_conn.instance.filter(InstanceIds=ids).stop()
ec2_conn.instance.filter(InstanceIds=ids).terminate()
