variable "capture_name_prefix" {
  type    = string
  default = "packer"
}

variable "client_id" {
  type    = string
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "dockerhub_login" {
  type    = string
      description = "The docker hub login, passed as a PKR_VAR"
}

variable "dockerhub_password" {
  type    = string
      description = "The docker hub password passed as a PKR_VAR"
}

variable "helper_script_folder" {
  type    = string
  default = "/imagegeneration/helpers"
}

variable "image_folder" {
  type    = string
  default = "/imagegeneration"
}

variable "image_os" {
  type    = string
  default = "ubuntu22"
}

variable "image_version" {
  type    = string
  default = "dev"
}

variable "imagedata_file" {
  type    = string
  default = "/imagegeneration/imagedata.json"
}

variable "installer_script_folder" {
  type    = string
  default = "/imagegeneration/installers"
}

variable "install_password" {
  type  = string
  default = ""
}

variable "location" {
  type    = string
  default = "West Europe"
}

variable "subscription_id" {
  type    = string
  default = "${env("ARM_SUBSCRIPTION_ID")}"
}

variable "tenant_id" {
  type    = string
  default = "${env("ARM_TENANT_ID")}"
}

variable "gallery_name" {
  type    = string
  description = "The gallery name, passed as a PKR_VAR"
}

variable "gallery_name_rg_name" {
  type    = string
    description = "The gallery resource group name, passed as a PKR_VAR"
}

source "azure-arm" "build" {

  client_id       = var.client_id
  client_secret   = var.client_secret
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  build_resource_group_name = var.gallery_rg_name

  os_type                   = "Linux"
  image_offer               = "lbdo-azdo-ubuntu-22.04"
  image_publisher           = "Libre DevOps"
  image_sku                 = "latest"
  vm_size                   = "Standard_D4s_v4"

  managed_image_name                = "lbdo-azdo-ubuntu-22.04-latest"
  managed_image_resource_group_name = var.gallery_rg_name

  plan_info {
    plan_name      = "cis-ubuntu2004-l1"
    plan_product   = "cis-ubuntu-linux-2004-l1"
    plan_publisher = "center-for-internet-security-inc"
  }

  shared_image_gallery_destination {
    gallery_name  = var.gallery_name
    image_name    = "lbdo-azdo-ubuntu-22.04-latest"
    image_version = var.image_version
    resource_group = var.gallery_rg_name
    subscription   = var.subscription_id
  }
}

build {
  sources = ["source.azure-arm.build_vhd"]

  # Creates a folder for the prep of the image - Needed
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mkdir ${var.image_folder}", "chmod 777 ${var.image_folder}"]
  }

  # Fixes an error in the Linux machine which causes the WALinuxAgent to break - https://github.com/Azure/azure-linux-extensions/issues/1238 - Needed
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/apt-mock.sh"
  }

  # Adds various repos to the image, such as the Microsoft one - Needed
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/base/repos.sh"]
  }

  # Preps a bunch of apt services - Needed
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script           = "${path.root}/scripts/base/apt.sh"
  }

  # Sets Pam limits - Potentially Unneeded
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/limits.sh"
  }

  # Creates folder - Needed
  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "${path.root}/scripts/helpers"
  }

  # Creates folder - Needed
  provisioner "file" {
    destination = "${var.installer_script_folder}"
    source      = "${path.root}/scripts/installers"
  }

  # Creates folder - Needed
  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/post-generation"
  }

  # Creates folder - Needed
  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/scripts/tests"
  }

  # Creates folder - Needed
  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/scripts/SoftwareReport"
  }

  # Loads JSON file with toolset within
  provisioner "file" {
    destination = "${var.installer_script_folder}/toolset.json"
    source      = "${path.root}/toolsets/toolset-2204.json"
  }

  # Primes image data file - Probably Unneeded
  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${var.imagedata_file}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/preimagedata.sh"]
  }

  # Configures OS environment - Needed
  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/configure-environment.sh"]
  }

  # Configures Snapstore (ew) - Needed
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/complete-snap-setup.sh", "${path.root}/scripts/installers/powershellcore.sh"]
  }

  # Install PowerShell Modules - Needed
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/Install-PowerShellModules.ps1", "${path.root}/scripts/installers/Install-AzureModules.ps1"]
  }

  # Installs Docker and Docker-Compose via Moby - Needed
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DOCKERHUB_LOGIN=${var.dockerhub_login}", "DOCKERHUB_PASSWORD=${var.dockerhub_password}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/docker-compose.sh", "${path.root}/scripts/installers/docker-moby.sh"]
  }

  # Installs packages added in the installers dir
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
                        "${path.root}/scripts/installers/azcopy.sh",
                        "${path.root}/scripts/installers/azure-cli.sh",
                        "${path.root}/scripts/installers/azure-devops-cli.sh",
                        "${path.root}/scripts/installers/basic.sh",
                        "${path.root}/scripts/installers/containers.sh",
                        "${path.root}/scripts/installers/dotnetcore-sdk.sh",
                        "${path.root}/scripts/installers/git.sh",
                        "${path.root}/scripts/installers/github-cli.sh",
                        "${path.root}/scripts/installers/kubernetes-tools.sh",
                        "${path.root}/scripts/installers/terraform.sh",
                        "${path.root}/scripts/installers/packer.sh",
                        "${path.root}/scripts/installers/vcpkg.sh",
                        "${path.root}/scripts/installers/dpkg-config.sh",
                        "${path.root}/scripts/installers/yq.sh",
                        "${path.root}/scripts/installers/pypy.sh",
                        "${path.root}/scripts/installers/python.sh",
                        ]
  }

  # Installs everything in toolset.json as part of the toolcache section (which is basically everything) - Needed
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/Install-Toolset.ps1", "${path.root}/scripts/installers/Configure-Toolset.ps1"]
  }

  # Installs everything in the PipX section - Needed
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/pipx-packages.sh"]
  }

  # Restarts the snapd - Needed
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/homebrew.sh"]
  }

  # Restarts the snapd - Needed
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/snap.sh"
  }

  # Reboots the VM - Needed
  provisioner "shell" {
    execute_command   = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    scripts           = ["${path.root}/scripts/base/reboot.sh"]
  }

  # Cleans up junk - Needed
  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/scripts/installers/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  # Removes apt mock - Needed
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/scripts/base/apt-mock-remove.sh"
  }

   # Runs Pester tests - Needed
  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    inline           = ["pwsh -File ${var.image_folder}/SoftwareReport/SoftwareReport.Generator.ps1 -OutputDirectory ${var.image_folder}", "pwsh -File ${var.image_folder}/tests/RunAll-Tests.ps1 -OutputDirectory ${var.image_folder}"]
  }

  # Adds readme - Probably Uneeded
  provisioner "file" {
    destination = "${path.root}/Ubuntu2204-Readme.md"
    direction   = "download"
    source      = "${var.image_folder}/Ubuntu-Readme.md"
  }

  # Post-deployment - Needed
  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/scripts/installers/post-deployment.sh"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["sleep 30", "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"]
  }
}
