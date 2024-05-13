// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

resource "aws_codepipeline" "this" {
  name     = var.pipeline_name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = module.artifact_s3.bucket.id
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName       = var.codecommit_repo
        BranchName           = var.branch
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Validation"

    dynamic "action" {
      for_each = local.validation_stages
      content {
        name            = action.key
        category        = "Test"
        owner           = "AWS"
        provider        = "CodeBuild"
        input_artifacts = ["source_output"]
        version         = "1"

        configuration = {
          ProjectName = module.validation[action.key].codebuild_project.name
        }
      }

    }

  }

  stage {
    name = "Plan"

    action {
      name            = "Plan"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.plan.codebuild_project.name
      }
    }
  }
  stage {
    name = "Approve"

    action {
      name     = "Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        CustomData         = "This action will approve the deployment of resources in ${var.pipeline_name}. Please ensure that you review the build logs of the plan stage before approving."
        ExternalEntityLink = "https://${data.aws_region.current.name}.console.aws.amazon.com/codesuite/codebuild/${data.aws_caller_identity.current.account_id}/projects/${var.pipeline_name}-plan/"
      }
    }
  }
  stage {
    name = "Apply"

    action {
      name            = "Apply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["source_output"]
      version         = "1"

      configuration = {
        ProjectName = module.apply.codebuild_project.name
      }
    }
  }
}


resource "aws_iam_role" "codepipeline_role" {
  name               = "${var.pipeline_name}-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline-assume-role.json
}

data "aws_iam_policy_document" "codepipeline-assume-role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "codepipeline" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline.arn
}

resource "aws_iam_role_policy_attachment" "cmk" {
  count      = var.kms_key_arn != null ? 1 : 0
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.cmk[0].arn
}

resource "aws_iam_policy" "cmk" {
  count  = var.kms_key_arn != null ? 1 : 0
  name   = "${var.pipeline_name}-cmk-role"
  policy = data.aws_iam_policy_document.cmk-policy[0].json
}

resource "aws_iam_policy" "codepipeline" {
  name   = "${var.pipeline_name}-role"
  policy = data.aws_iam_policy_document.codepipeline-policy.json
}

data "aws_iam_policy_document" "codepipeline-policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObjectAcl",
      "s3:PutObject"
    ]

    resources = [
      "${module.artifact_s3.bucket.arn}",
      "${module.artifact_s3.bucket.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "codecommit:GetBranch",
      "codecommit:GetCommit",
      "codecommit:UploadArchive",
      "codecommit:GetUploadArchiveStatus",
      "codecommit:CancelUploadArchive"
    ]

    resources = [
      "arn:aws:codecommit:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.codecommit_repo}"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild"
    ]

    resources = [
      "arn:aws:codebuild:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:project/${var.pipeline_name}-*"
    ]
  }

}


data "aws_iam_policy_document" "cmk-policy" {
  count = var.kms_key_arn != null ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:Decrypt"
    ]

    resources = [
      "${var.kms_key_arn}"
    ]
  }

}

module "artifact_s3" {
  source            = "./modules/s3"
  bucket_name       = "${var.pipeline_name}-artifacts-${data.aws_caller_identity.current.account_id}"
  enable_retention  = true
  retention_in_days = "90"
}