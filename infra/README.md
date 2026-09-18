# infra

Terraform for the poc-aws project. Free-tier only. State is local
(`terraform.tfstate`, gitignored) — fine for a solo POC.

## What this does NOT do

The EC2 instance (`i-02493c4d817d45bf4`) is pre-existing (created via the
console) and is **not** imported into Terraform. Terraform only creates
free-standing resources (new security group, IAM instance profile, S3
buckets, OIDC/IAM roles, CloudTrail, patch baseline). Attaching the new SG
and instance profile to the instance is a manual step below, by design —
importing a hand-created instance risks Terraform proposing a destructive
replace later if some attribute doesn't match.

## First-time setup

```
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set admin_cidr to your current IP/32

terraform init
terraform plan   # review carefully: should be all "create", never "destroy"
terraform apply
```

## Manual cutover (run once, in this order)

1. **Start the instance** if it's stopped (Console or
   `aws ec2 start-instances --instance-ids i-02493c4d817d45bf4`).

2. **Attach the new instance profile only** (SG untouched, SSH still works
   as a fallback):
   ```
   aws ec2 associate-iam-instance-profile \
     --instance-id i-02493c4d817d45bf4 \
     --iam-instance-profile Name=$(terraform output -raw instance_profile_name)
   ```

3. **Verify SSM works before touching the security group**:
   ```
   aws ssm start-session --target i-02493c4d817d45bf4
   ```
   If this doesn't connect within ~1-2 minutes of the instance being up,
   stop here and debug (SSM agent status, IAM role) before proceeding —
   do not close SSH until this works.

4. **Swap the security group** (this is the point SSH access actually
   closes — the new SG has no port 22 rule at all):
   ```
   aws ec2 modify-instance-attribute \
     --instance-id i-02493c4d817d45bf4 \
     --groups $(terraform output -raw security_group_id)
   ```
   Re-run `aws ssm start-session --target i-02493c4d817d45bf4` to confirm
   it still works with the new SG.

5. **Tag the instance for patching**:
   ```
   aws ec2 create-tags --resources i-02493c4d817d45bf4 \
     --tags Key="Patch Group",Value=$(terraform output -raw patch_group_tag_value)
   ```

Filesystem bootstrap for the app itself lives with the app now -
see `../demo-app/README.md` and `../RUN.md`.

## Cleanup (after a few successful deploys)

Delete the now-unattached original security group (`launch-wizard-1`) once
you're confident the new setup is stable:
```
aws ec2 delete-security-group --group-id sg-00ac13bdd14e152e6
```

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

See `../RUN.md` for the commands used to set this up.

## Deferred / not built here

- Remote Terraform state backend (S3 + lock table) — local state is fine solo.
- `terraform plan` on PRs in CI — would need a second, read-only IAM role.
