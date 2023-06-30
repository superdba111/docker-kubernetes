import boto3
import paramiko
import csv
import json
import psycopg2
from datetime import datetime


def get_file_name():
    now = datetime.now()
    month = now.strftime("%B")
    day = now.strftime("%d")
    file_name = f"blackline_{month}{day}.csv"
    return file_name


def main():
    # Blackline SFTP server information
    aws_sm_client1 = boto3.client('secretsmanager')
    response1 = aws_sm_client1.get_secret_value(SecretId='sftp/blackline')
    secretDict1 = json.loads(response1['SecretString'])

    sftp_host = secretDict1['sftp_host']
    sftp_username = secretDict1['sftp_username']
    sftp_password = secretDict1['sftp_password']
    sftp_folder = secretDict1['sftp_folder']

    # Connect to Redshift and execute query
    aws_sm_client2 = boto3.client('secretsmanager')
    response2 = aws_sm_client2.get_secret_value(SecretId='datalake/redshift/glue_job')

    # Retrieve the Redshift database credentials from AWS Secrets Manager
    secretDict2 = json.loads(response2['SecretString'])
    username = secretDict2['username']
    password = secretDict2['password']
    host = secretDict2['host']
    port = secretDict2['port']
    database = secretDict2['database']

    print("before connecting to redshift")

    conn = psycopg2.connect(
        host=host,
        port=port,
        database=database,
        user=username,
        password=password
    )

    cursor = conn.cursor()

    print("after connecting  to redshift")

    query_str = '''
        SELECT 
            Auction_item_id, 
            auction_item_status, 
            purchase_price, 
            transaction_number, 
            transaction_number, 
            sold_date,auction, 
            currency_code, 
            buy_fee_credit, 
            buy_sub_total, 
            buyer_total, 
            transport_fee, 
            buyer_assurance_fee_original, 
            seller_assurance_fee_original, 
            sell_arbitration_insurance_fee, 
            sell_fee, 
            buy_fee, 
            buy_psi_fee, 
            vin, 
            seller, 
            buyer, 
            collect_title_task_status, 
            arbitration_zendesk_ticket_id 
        FROM dw.vw_office_operation
        WHERE auction_item_status='SOLD'
        AND sold_date BETWEEN '2023-01-01' AND '2023-12-31'
    '''

    print(query_str)
    cursor.execute(query_str)

    print("using the cursor execute the query")
    results = cursor.fetchall()

    print("Fetching all data....")

    # Specify the local file path to save the results
    myfile = get_file_name()
    print("The file name is" + myfile)
    file_path = f'./data/{myfile}'

    print("before writing the file ....")

    # Save the results to a CSV file
    with open(file_path, 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)

        # Write the column headers
        writer.writerow([desc[0] for desc in cursor.description])

        # Write the data rows
        for record in results:
            writer.writerow(record)

    print(f"Query results saved to: {file_path}")
    print("before connecting SFTP ....")

    # Connect to Blackline SFTP server
    transport = paramiko.Transport((sftp_host, 22))
    transport.connect(username=sftp_username, password=sftp_password)
    sftp = paramiko.SFTPClient.from_transport(transport)

    # Upload file to SFTP folder
    sftp.chdir(sftp_folder)
    sftp.put(file_path, myfile)

    # Close connections
    sftp.close()
    transport.close()
    cursor.close()
    conn.close()

    print("The job is complete")

    return 'File transfer from Redshift to Blackline SFTP complete.'


main()