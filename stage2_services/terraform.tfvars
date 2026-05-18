# ── AWS ───────────────────────────────────────────────────────────────────────
aws_region = "us-east-1"

# ── From stage1 outputs (run: cd stage1_infrastructure && terraform output) ───

# terraform output vpc_id
vpc_id = "FILL_FROM_STAGE1_OUTPUT"

# terraform output -json public_subnet_ids
public_subnet_ids = ["FILL_SUBNET_1", "FILL_SUBNET_2"]

# terraform output ecs_security_group_id
ecs_security_group_id = "FILL_FROM_STAGE1_OUTPUT"

# terraform output alb_security_group_id
alb_security_group_id = "FILL_FROM_STAGE1_OUTPUT"

# terraform output rds_host
rds_host = "FILL_FROM_STAGE1_OUTPUT"

# terraform output dynamodb_table_name
dynamodb_table_name = "notifications"

# terraform output s3_bucket_name
s3_bucket_name = "FILL_FROM_STAGE1_OUTPUT"

# ── Secrets (never commit real values) ───────────────────────────────────────

db_username = "postgres"

# Set via: export TF_VAR_db_password="your-password"
db_password = "CHANGE_ME"

# CloudAMQP URL from your CloudAMQP dashboard (Settings > AMQP details)
# Set via: export TF_VAR_rabbitmq_url="amqps://..."
rabbitmq_url = "amqps://CHANGE_ME"

# ── Inter-service URLs (optional — fill after first deploy) ──────────────────
# These can be left empty initially and updated once tasks have running IPs,
# or replaced with AWS Cloud Map service discovery endpoints.

order_service_url        = ""
inventory_service_url    = ""
payment_service_url      = ""
notification_service_url = ""
