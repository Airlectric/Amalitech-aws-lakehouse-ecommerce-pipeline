output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet (holds the NAT Gateway)"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet (Glue + Lambda compute)"
  value       = aws_subnet.private.id
}

output "isolated_subnet_id" {
  description = "ID of the isolated subnet (no internet route — S3/DDB via gateway endpoints only)"
  value       = aws_subnet.isolated.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "security_group_endpoints_id" {
  description = "ID of the VPC endpoints security group"
  value       = aws_security_group.endpoints.id
}

output "security_group_glue_id" {
  description = "ID of the Glue security group"
  value       = aws_security_group.glue.id
}

output "security_group_lambda_id" {
  description = "ID of the Lambda security group"
  value       = aws_security_group.lambda.id
}

output "route_table_public_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "route_table_private_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "route_table_isolated_id" {
  description = "ID of the isolated route table"
  value       = aws_route_table.isolated.id
}

output "endpoint_gateway_ids" {
  description = "Map of gateway endpoint IDs by service name"
  value = {
    for k, e in aws_vpc_endpoint.gateway : k => e.id
  }
}

output "endpoint_interface_ids" {
  description = "Map of interface endpoint IDs by service name"
  value = {
    for k, e in aws_vpc_endpoint.interface : k => e.id
  }
}

output "flow_log_group_name" {
  description = "CloudWatch log group name for VPC flow logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "glue_az" {
  description = "Availability zone of the private subnet used by the Glue NETWORK connection"
  value       = aws_subnet.private.availability_zone
}
