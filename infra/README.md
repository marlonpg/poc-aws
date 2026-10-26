# infra

Terraform for the poc-aws project. Free-tier only. State is local
(`terraform.tfstate`, gitignored) — fine for a solo POC.

## What this manages

Everything, including the EC2 instance itself (`aws_instance.app`,
`infra/ec2_instance.tf`). This used to be a hand-created instance that
Terraform only looked up via a data source - it's since been recreated as
a fully Terraform-owned resource: AMI lookup, security group, IAM instance
profile, and first-boot provisioning (`user_data`, built from
`demo-common/bootstrap-common.sh` + each service's `deploy.sh`) are all
declared here. `terraform apply` is the entire setup - no manual
attach/swap/tag steps, no SSH, no SSM command needed to get from zero to a
working demo. See `../RUN.md` for day-2 operations (start/stop, redeploys,
break/fix).

**AMI filter gotcha**: must resolve to the standard AMI
(`al2023-ami-2023.*-x86_64`), not `al2023-ami-minimal-*` - the minimal
variant doesn't ship the SSM Agent, which silently breaks every SSM-based
command. Learned this the hard way once; see the comment in
`ec2_instance.tf`.

## First-time setup

```
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set admin_cidr to your current IP/32

terraform init
terraform plan   # review carefully: should be all "create", never "destroy"
terraform apply
```

That's it - the instance self-provisions on first boot (~1-2 min for
package installs). `../RUN.md` has verification commands.

## Local CLI auth: `pocaws-admin`, not root

`terraform apply`/`aws` commands run as the IAM user `pocaws-admin`
(the `default` CLI profile), not the account root user. Root's access key
is deactivated. `pocaws-admin` has two policies attached:

- AWS managed `PowerUserAccess` (everything except IAM/Organizations/Account).
- A custom policy, `pocaws-terraform-iam`, scoped to just this project's IAM
  resources (needed because PowerUserAccess deliberately excludes IAM):

  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "ManageProjectRolesAndProfiles",
        "Effect": "Allow",
        "Action": [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole", "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:TagInstanceProfile"
        ],
        "Resource": [
          "arn:aws:iam::*:role/pocaws-*",
          "arn:aws:iam::*:instance-profile/pocaws-*"
        ]
      },
      {
        "Sid": "ManageGithubOidcProvider",
        "Effect": "Allow",
        "Action": [
          "iam:CreateOpenIDConnectProvider", "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider", "iam:TagOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider"
        ],
        "Resource": "arn:aws:iam::*:oidc-provider/token.actions.githubusercontent.com"
      },
      {
        "Sid": "PassProjectRolesToServices",
        "Effect": "Allow",
        "Action": "iam:PassRole",
        "Resource": "arn:aws:iam::*:role/pocaws-*"
      },
      {
        "Sid": "ListOnlyNoResourceLevelSupport",
        "Effect": "Allow",
        "Action": ["iam:ListRoles", "iam:ListOpenIDConnectProviders"],
        "Resource": "*"
      }
    ]
  }
  ```

  **Known unused leftover**: `ManageGithubOidcProvider` and the
  `iam:ListOpenIDConnectProviders` action became dead permissions once
  `infra/iam_github_oidc.tf` was removed (the OIDC provider/GHA deploy role
  it managed no longer exist). `pocaws-admin` can't trim its own policy
  (no `iam:*PolicyVersion` grant - by design, it can't self-escalate), so
  removing this requires either the account owner editing the policy in
  the Console, or briefly reactivating the deactivated root key. Left as-is
  since it's a dangling permission, not a live resource or active risk.

See `../RUN.md` for the commands used to set this up.

## Deferred / not built here

- Remote Terraform state backend (S3 + lock table) — local state is fine solo.
- `terraform plan` on PRs in CI — would need a second, read-only IAM role.
