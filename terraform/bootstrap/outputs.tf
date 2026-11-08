output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "lock_table" { value = aws_dynamodb_table.lock.name }
output "github_actions_role_arn" { value = aws_iam_role.gha.arn }
