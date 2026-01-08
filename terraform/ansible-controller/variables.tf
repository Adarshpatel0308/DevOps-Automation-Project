
variable "region"        { type = string; default = "us-east-1" }
variable "project"       { type = string; default = "devops-k8s" }
variable "ami_id"        { type = string; default = "ami-08c40ec9ead489470" } # Ubuntu 22.04 us-east-1
variable "instance_type" { type = string; default = "t3.micro" }
variable "key_name"      { type = string; default = "jenkins-keypair" }       # MUST exist in us-east-1
