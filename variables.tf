// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

variable "pipeline_name" {
  type = string
}

variable "codecommit_repo" {
  type = string
}

variable "branch" {
  type    = string
  default = "main"
}

variable "environment_variables" {
  description = "environment variables for codebuild"
  type        = map(string)
  default = {
    TF_VERSION     = "1.5.7"
    TFLINT_VERSION = "0.33.0"
  }
}

variable "checkov_skip" {
  description = "list of checkov checks to skip"
  type        = list(string)
  default     = [""]
}

variable "kms_key_arn" {
  default     = null
  description = "Customer Managed Key (CMK) ARN used for the provided CodeCommit repository. This will update the IAM role to have the correct permissions. The CMK will need to be updated separately."
  type        = string
}