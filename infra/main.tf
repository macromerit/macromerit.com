terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "macromerit-admin"
}

variable "prefix" {
  type    = string
  default = "macromerit"
}

variable "domain_name" {
  type    = string
  default = "macromerit.com"
}

# ── ACM Certificate (must be us-east-1 for CloudFront) ──

resource "aws_acm_certificate" "frontend" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# ── S3 Bucket ────────────────────────────────────────────

resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.prefix}-frontend"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── CloudFront OAI + Bucket Policy ──────────────────────

resource "aws_cloudfront_origin_access_identity" "frontend" {
  comment = "${var.prefix} frontend"
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontAccess"
      Effect    = "Allow"
      Principal = { AWS = aws_cloudfront_origin_access_identity.frontend.iam_arn }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

# ── Response Headers (noindex while in preview) ─────────

resource "aws_cloudfront_response_headers_policy" "noindex" {
  name = "${var.prefix}-noindex"

  custom_headers_config {
    items {
      header   = "X-Robots-Tag"
      value    = "noindex, nofollow"
      override = true
    }
  }
}

# ── CloudFront Distribution ─────────────────────────────

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]

  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "s3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.frontend.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods                = ["GET", "HEAD"]
    cached_methods                 = ["GET", "HEAD"]
    target_origin_id               = "s3"
    viewer_protocol_policy         = "redirect-to-https"
    response_headers_policy_id     = aws_cloudfront_response_headers_policy.noindex.id

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # SPA-style: serve index.html for 404s (single-page site)
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.frontend.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ── Outputs ──────────────────────────────────────────────

output "cloudfront_domain" {
  description = "Share this URL with friends and family"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.frontend.id
}

output "s3_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "acm_validation_records" {
  description = "Add these CNAME records in Cloudflare to validate the SSL certificate"
  value = [
    for dvo in aws_acm_certificate.frontend.domain_validation_options : {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  ]
}

output "go_live_cname" {
  description = "When ready to go public: add this CNAME in Cloudflare for macromerit.com"
  value = {
    name  = var.domain_name
    type  = "CNAME"
    value = aws_cloudfront_distribution.frontend.domain_name
  }
}
