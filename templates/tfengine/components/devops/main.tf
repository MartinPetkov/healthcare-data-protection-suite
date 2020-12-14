# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This folder contains Terraform resources to setup the devops project, which includes:
# - The project itself,
# - APIs to enable,
# - Deletion lien,
# - Project level IAM permissions for the project owners,
# - A Cloud Storage bucket to store Terraform states for all deployments,
# - Admin permission at {{.parent_type}} level,
# - Cloud Identity groups and memberships, if requested.

// TODO: replace with https://github.com/terraform-google-modules/terraform-google-bootstrap
terraform {
  required_version = ">=0.12, <0.14"
  required_providers {
    google      = "~> 3.0"
    google-beta = "~> 3.0"
  }
{{- if get . "enable_gcs_backend"}}
  backend "gcs" {
    bucket = "{{.state_bucket}}"
    prefix = "devops"
  }
{{- end}}
}

{{- if or (not (get .admins_group "exists" false)) (not (get .project.owners_group "exists" false))}}

# Required when using end-user ADCs (Application Default Credentials) to manage Cloud Identity groups and memberships.
provider "google-beta" {
  user_project_override = true
  billing_project       = "{{.project.project_id}}"
}
{{- end}}

# Create the project, enable APIs, and create the deletion lien, if specified.
module "project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 9.2.0"

  name                    = "{{.project.project_id}}"
  {{- if eq .parent_type "organization"}}
  org_id                  = "{{.parent_id}}"
  {{- else}}
  org_id                  = ""
  folder_id               = "{{.parent_id}}"
  {{- end}}
  billing_account         = "{{.billing_account}}"
  lien                    = {{get . "enable_lien" true}}
  default_service_account = "keep"
  skip_gcloud_download    = true
  activate_apis = [
    "cloudbuild.googleapis.com",
    {{range get . "project.apis" -}}
    "{{.}}",
    {{end -}}
  ]
}

# Terraform state bucket, hosted in the devops project.
module "state_bucket" {
source  = "terraform-google-modules/cloud-storage/google//modules/simple_bucket"
  version = "~> 1.4"

  name       = "{{.state_bucket}}"
  project_id = module.project.project_id
  location   = "{{.storage_location}}"
}

{{- if not (get .project.owners_group "exists" false)}}

# Devops project owners group.
module "owners_group" {
  source  = "terraform-google-modules/group/google"
  version = "~> 0.1"

  id = "{{.project.owners_group.id}}"
  customer_id = "{{.project.owners_group.customer_id}}"
  {{hclField .project.owners_group "description" -}}
  {{hclField .project.owners_group "display_name" -}}
  {{hclField .project.owners_group "owners" -}}
  {{hclField .project.owners_group "managers" -}}
  {{hclField .project.owners_group "members" -}}
  depends_on = [
    module.project
  ]
}
{{- end}}

# Project level IAM permissions for devops project owners.
resource "google_project_iam_binding" "devops_owners" {
  project = module.project.project_id
  role    = "roles/owner"
  members = [{{if get .project.owners_group "exists" false}} "group:{{.project.owners_group.id}}" {{else}} "group:${module.owners_group.id}" {{end}}]
}

{{- if not (get .admins_group "exists" false)}}

# Admins group for at {{.parent_type}} level.
module "admins_group" {
  source  = "terraform-google-modules/group/google"
  version = "~> 0.1"

  id = "{{.admins_group.id}}"
  customer_id = "{{.admins_group.customer_id}}"
  {{hclField .admins_group "description" -}}
  {{hclField .admins_group "display_name" -}}
  {{hclField .admins_group "owners" -}}
  {{hclField .admins_group "managers" -}}
  {{hclField .admins_group "members" -}}
  depends_on = [
    module.project
  ]
}
{{- end}}

# Admin permission at {{.parent_type}} level.
resource "google_{{.parent_type}}_iam_member" "admin" {
  {{- if eq .parent_type "organization"}}
  org_id = "{{.parent_id}}"
  {{- else}}
  folder = "folders/{{.parent_id}}"
  {{- end}}
  role   = "roles/resourcemanager.{{.parent_type}}Admin"
  member = {{if get .admins_group "exists" false}} "group:{{.admins_group.id}}" {{else}} "group:${module.admins_group.id}" {{end}}
}
