from email.parser import BytesParser
from email.message import EmailMessage
from email import policy
import os
import boto3



# event will be JSON from SES incoming email rule - NOT an S3 PUT event
def lambda_handler(event, context):

    ses_mail = event['Records'][0]['ses']['mail']
    receipt = event['Records'][0]['ses']['receipt']
    message_id = ses_mail['messageId']
    print('Commencing processing for message {}'.format(message_id))

    statuses = [
        receipt['spamVerdict']['status'], 
        receipt['virusVerdict']['status'],
        receipt['spfVerdict']['status'], 
        receipt['dkimVerdict']['status']
    ]

    if 'FAIL' in statuses:
        print('Email failed one of the security tests. Quitting.')
        raise Exception('Message failed to pass the appropriate security checks - ceasing processing of message.')

    # if we get here then we have passed all the tests so we can now process the message
    bucket_name = os.environ['BUCKET']
    s3 = boto3.resource('s3')
    bucket = s3.Bucket(bucket_name)
    raw_email = bucket.Object(os.environ['SES_S3_BUCKET_PREFIX'] + message_id).get()['Body'].read()
    msg = BytesParser(policy=policy.SMTP).parsebytes(raw_email)

    for part in msg.walk():
        if part.get_content_maintype() == 'multipart' or part.get('Content-Disposition') is None:
            continue
        if part.get_filename():
            print(part.get_filename())
            print(part.get_payload(decode=True))
    return True