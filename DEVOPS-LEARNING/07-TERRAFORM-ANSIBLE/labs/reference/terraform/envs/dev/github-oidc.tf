# GitHub Actions → AWS không cần access key: OIDC provider + role chỉ workflow trong
# environment "production" của đúng repo mới đảm nhận được (giống bản tạo tay ở v3).

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Không khai báo thumbprint_list: với GitHub, AWS xác thực bằng thư viện root CA của chính AWS
  # (tài liệu provider aws_iam_openid_connect_provider).
}

data "aws_iam_policy_document" "github_deploy_trust" {
  statement {
    sid     = "GitHubActionsProductionEnvironmentOnly"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:environment:production"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${local.name_prefix}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_trust.json
}

data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "OnlyTheRunShellScriptDocument"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"]
  }

  statement {
    sid       = "OnlyInstancesTaggedProject"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Project"
      values   = [var.project]
    }
  }

  statement {
    sid       = "ReadCommandResults"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }

  statement {
    sid       = "FindTheInstance"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${local.name_prefix}-github-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
