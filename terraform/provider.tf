terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  backend "gcs" {
    bucket = "esmos-healthcare-tfstate"
    prefix = "terraform/state"
  }
}

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  default = "asia-southeast1"
}

variable "project_name" {
  default = "esmos-healthcare"
}

variable "db_admin_password" {
  type      = string
  sensitive = true
}

provider "google" {
  project = var.project_id
  region  = var.region
}
