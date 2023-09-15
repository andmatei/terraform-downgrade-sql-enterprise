variable "instance_id" {
  type = string
  description = "The ID of instance which has SQL Enterprise installed."
}

variable "inplace_downgrade" {
  type = bool
  description = "Should be true if the downgrade should be executed on the same instance"
  default = false
}

variable "sql_sa_user" {
  type = string
  description = "The SQL SA User used to connect to the SQL database"
  default = "awsadmin"
}

variable "sql_sa_password" {
  type = string
  description = "The SQL SA Password used to connecto to the SQL database"
  default = "awsadmin123"
}

variable "sql_installation_folder" {
  type = string
  description = "The installation forlder for SQL"
  default = "D:\\AWS\\SS2K19_SE\\SETUP.EXE"
}

variable "sql_source_edition" {
  type = string
  description = "The SQL edition installed on the instance"
  default = "Standard"
}

variable "tags" {
  description = "Map of tags to add to all resources"
  type        = map(string)
  default     = {}
}