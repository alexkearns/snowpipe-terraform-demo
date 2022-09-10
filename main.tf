terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.30.0"
    }
    snowflake = {
      source = "snowflake-labs/snowflake"
      version = "0.43.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

provider "snowflake" {
  username = var.snowflake_username
  password = var.snowflake_password
  account  = var.snowflake_account
  region   = var.snowflake_region
  role  = "ACCOUNTADMIN"
}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
}

# 1. Create an S3 bucket

resource "aws_s3_bucket" "snowpipe_source" {
  bucket = "snowpipe-source-${local.aws_account_id}"
}

resource "aws_s3_bucket_acl" "snowpipe_source" {
  bucket = aws_s3_bucket.snowpipe_source.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "snowpipe_source" {
  bucket = aws_s3_bucket.snowpipe_source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. Create a Snowflake storage integration

resource snowflake_storage_integration integration {
  name    = "demo"
  comment = "Connects to the ${aws_s3_bucket.snowpipe_source.id} S3 bucket"
  type    = "EXTERNAL_STAGE"

  enabled = true

  storage_allowed_locations = ["s3://${aws_s3_bucket.snowpipe_source.id}"]
  storage_aws_object_acl    = "bucket-owner-full-control"

  storage_provider         = "S3"
  storage_aws_role_arn     = "arn:aws:iam::${local.aws_account_id}:role/${var.aws_role_name}"
}

# 3. Create the role in AWS that the storage integration uses

resource "aws_iam_role" "storage_integration_role" {
  name = var.aws_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = snowflake_storage_integration.integration.storage_aws_iam_user_arn
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = snowflake_storage_integration.integration.storage_aws_external_id
          }
        }
      },
    ]
  })

  inline_policy {
    name = "BucketAccessInlinePolicy"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = [
            "s3:GetObject",
            "s3:GetObjectVersion"
          ]
          Effect   = "Allow"
          Resource = "${aws_s3_bucket.snowpipe_source.arn}/*"
        },
        {
          Action   = [
            "s3:ListBucket",
            "s3:GetBucketLocation"
          ]
          Effect   = "Allow"
          Resource = aws_s3_bucket.snowpipe_source.arn
        }
      ]
    })
  }
}

# 4. Create a Snowflake stage that is pointed at the S3 bucket we've created

resource "snowflake_stage" "demo_stage" {
  name        = "DEMO_STAGE"
  url         = "s3://${aws_s3_bucket.snowpipe_source.id}"
  database    = var.snowflake_database
  schema      = var.snowflake_schema
  storage_integration = snowflake_storage_integration.integration.name
}

# 5. Create a target Snowflake table

resource "snowflake_table" "demo_table" {
  database            = var.snowflake_database
  schema              = var.snowflake_schema
  name                = "demo_table"
  comment             = "A demo target table."

  column {
    name     = "first_name"
    type     = "VARCHAR(255)"
    nullable = false
  }

  column {
    name     = "last_name"
    type     = "VARCHAR(255)"
    nullable = false
  }

  column {
    name     = "email_address"
    type     = "VARCHAR(255)"
    nullable = false
  }
}

# 6. Create a Snowpipe

resource "snowflake_pipe" "demo_pipe" {
  database = var.snowflake_database
  schema   = var.snowflake_schema
  name     = "demo_pipe"

  comment = "A pipe to ingest data from the ${aws_s3_bucket.snowpipe_source.id} S3 bucket"

  copy_statement = "COPY INTO ${var.snowflake_database}.${var.snowflake_schema}.\"${snowflake_table.demo_table.name}\" FROM @${var.snowflake_database}.${var.snowflake_schema}.${snowflake_stage.demo_stage.name} file_format = (type = 'CSV')"
  auto_ingest    = true
}

# 7. Setup the S3 event notification

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.snowpipe_source.id

  queue {
    queue_arn     = snowflake_pipe.demo_pipe.notification_channel
    events        = ["s3:ObjectCreated:*"]
  }
}

# 8. Upload a file to S3 to trigger the beginning of the process

resource "aws_s3_object" "sample_data_1" {
  bucket = aws_s3_bucket.snowpipe_source.id
  key    = "sample_data_1.csv"
  source = "./sample_data/sample_data_1.csv"

  etag = filemd5("./sample_data/sample_data_1.csv")
}