variable "instance_id" {
  type = string
  description = "ID of instance which has SQL Enterprise installed."
}

variable "sql_sa_user" {
  type = string
  description = "SQL SA User"
  default = "awsadmin"
}

variable "sql_sa_password" {
  type = string
  description = "SQL SA Password"
  default = "awsadmin"
}

variable "sql_installation_folder" {
  type = string
  description = "SQL Installation folder"
  default = "D:\\AWS\\SS2K19_SE\\SETUP.EXE"
}

variable "sql_source_edition" {
  type = string
  description = "SQL Source Edition"
  default = "Standard"
}