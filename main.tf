data "aws_route53_zone" "parent" {
    name = "robarthur.co.uk"
}

resource "aws_ses_domain_identity" "ses_domain" {
  domain = var.domain
}

resource "aws_route53_record" "amazonses_verification_record" {

  zone_id = data.aws_route53_zone.parent.zone_id
  name    = "_amazonses.${var.domain}"
  type    = "TXT"
  ttl     = "600"
  records = [join("", aws_ses_domain_identity.ses_domain.*.verification_token)]
}

resource "aws_ses_domain_dkim" "ses_domain_dkim" {
  domain = join("", aws_ses_domain_identity.ses_domain.*.domain)
}

resource "aws_route53_record" "amazonses_dkim_record" {
  count   = 3
  zone_id = data.aws_route53_zone.parent.zone_id
  name    ="${element(aws_ses_domain_dkim.ses_domain_dkim.dkim_tokens, count.index)}._domainkey.mail"
  type    = "CNAME"
  ttl     = "600"
  records =  ["${element(aws_ses_domain_dkim.ses_domain_dkim.dkim_tokens, count.index)}.dkim.amazonses.com"]
}

data "aws_region" "current" {
}

# Receiving MX Record
resource "aws_route53_record" "mx_receive" {
  name    = var.domain
  zone_id = data.aws_route53_zone.parent.zone_id
  type    = "MX"
  ttl     = "600"
  records = ["10 inbound-smtp.${data.aws_region.current.name}.amazonaws.com"]
}

resource "aws_s3_bucket" "email" {
  bucket_prefix = "email"
  force_destroy = true
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.email.bucket
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowSESPuts",
            "Effect": "Allow",
            "Principal": {
                "Service": "ses.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${aws_s3_bucket.email.bucket}/*"
        }
    ]
}
POLICY
}


resource "aws_s3_bucket_acl" "email" {
  bucket = aws_s3_bucket.email.id
  acl    = "private"
}

resource "aws_kms_key" "email" {
  description             = "Server side encryption of emails received in SES"
  deletion_window_in_days = 10
}

resource "aws_s3_bucket_server_side_encryption_configuration" "email" {
  bucket = aws_s3_bucket.email.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_ses_receipt_rule" "store" {
  name          = "store"
  rule_set_name = "default-rule-set"
  recipients    = ["data@${var.domain}"]
  tls_policy =  "Require"
  enabled       = true
  scan_enabled  = true

  s3_action {
    bucket_name = aws_s3_bucket.email.bucket
    object_key_prefix = "raw/"
    position    = 1
  }
}

