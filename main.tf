#################################
# Providers
#################################

provider "aws" {
  region = "us-east-1"
}

# Required for CloudFront ACM (must be us-east-1)
provider "aws" {
  alias  = "us_east"
  region = "us-east-1"
}

#################################
# S3 Bucket
#################################

resource "aws_s3_bucket" "website" {
  bucket = "demo-surya-01"
}

# ACL (new method)
resource "aws_s3_bucket_acl" "website_acl" {
  bucket = aws_s3_bucket.website.id
  acl    = "public-read"
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_policy" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.website.arn}/*"
    }]
  })
}

#################################
# Route53 Hosted Zone
#################################

resource "aws_route53_zone" "prabhaj" {
  name = "prabhaj.shop"
}

#################################
# ACM Certificate (SSL)
#################################

resource "aws_acm_certificate" "certificate" {
  provider          = aws.us_east
  domain_name       = "prabhaj.shop"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.prabhaj.shop"
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# DNS Validation (correct way using for_each)
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.certificate.domain_validation_options :
    dvo.domain_name => dvo
  }

  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  zone_id = aws_route53_zone.prabhaj.zone_id
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "certificate" {
  provider                = aws.us_east
  certificate_arn         = aws_acm_certificate.certificate.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

#################################
# CloudFront Distribution
#################################

resource "aws_cloudfront_distribution" "website" {

  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [
    "prabhaj.shop",
    "*.prabhaj.shop"
  ]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3Origin"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.certificate.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.certificate]
}

#################################
# Route53 Records -> CloudFront
#################################

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.prabhaj.zone_id
  name    = "prabhaj.shop"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "wildcard" {
  zone_id = aws_route53_zone.prabhaj.zone_id
  name    = "*.prabhaj.shop"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}
