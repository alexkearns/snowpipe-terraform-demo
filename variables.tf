variable "aws_region" {
  type = string
  description = "The AWS region to deploy to"
}

variable "aws_role_name" {
  type = string
  description = "The name of the role to create in AWS"
}

variable "snowflake_database" {
  type = string
  description = "The Snowflake database to use"
}

variable "snowflake_schema" {
  type = string
  description = "The Snowflake schema to use"
}

variable "snowflake_region" {
  type = string
  description = "The Snowflake region to connect to"
}

variable "snowflake_account" {
  type = string
  description = "The Snowflake account"
  sensitive = true
}

variable "snowflake_username" {
  type = string
  description = "Snowflake username to use for connecting"
  sensitive = true
}

variable "snowflake_password" {
  type = string
  description = "Snowflake password to use for connecting"
  sensitive = true
}