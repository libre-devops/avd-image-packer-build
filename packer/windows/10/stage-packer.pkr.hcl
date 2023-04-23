##### Build Variables  #####

variable "agent_tools_directory" {
  type    = string
  default = "C:\\hostedtoolcache\\windows"
  description = "The place where tools will be installed on the image - needed"
}

variable "imagedata_file" {
  type    = string
  default = "C:\\imagedata.json"
  description = "Where image data is stored - needed"
}

variable "helper_script_folder" {
  type    = string
  default = "C:\\Program Files\\WindowsPowerShell\\Modules\\"
  description = "Where the helper scripts from the build will be stored - needed"
}

variable "image_folder" {
  type    = string
  default = "C:\\image"
  description = "The image folder - needed"
}

variable "install_password" {
  type      = string
  sensitive = true
  description = "The initial installed password used - needed"
}

variable "install_user" {
  type    = string
  default = "installer"
  description = "The initial user used to install stuff - needed"
}

locals {
  image_version = formatdate("YYYY.MM.DD", timestamp())
  image_os  = "windows10"
}

###### Packer Variables ######

variable "location" {
  type        = string
  default     = "West Europe"
  description = "Used in scripts"
}

// Uses the packer env inbuilt function - https://www.packer.io/docs/templates/hcl_templates/functions/contextual/env
variable "client_id" {
  type        = string
  description = "The client id, passed as a PKR_VAR"
  default     = env("ARM_CLIENT_ID")
}

variable "client_secret" {
  type        = string
  sensitive   = true
  description = "The client_secret, passed as a PKR_VAR"
  default     = env("ARM_CLIENT_SECRET")
}

variable "subscription_id" {
  type        = string
  description = "The gallery resource group name, passed as a PKR_VAR"
  default     = env("ARM_SUBSCRIPTION_ID")
}

variable "tenant_id" {
  type        = string
  description = "The gallery resource group name, passed as a PKR_VAR"
  default     = env("ARM_TENANT_ID")
}

variable "gallery_name" {
  type        = string
  default     = "galldoeuwuat01"
  description = "The wgallery name"
}

variable "gallery_rg_name" {
  type        = string
  default     = "rg-ldo-euw-uat-build"
  description = "The gallery resource group name"
}

variable "virtual_network_name" {
  type        = string
  default     = "vnet-ldo-euw-uat-01"
  description = "The name of the vnet"
}

variable "virtual_network_resource_group_name" {
  type        = string
  default     = "rg-ldo-euw-uat-build"
  description = "The name of the resource group the vnet is in"
}

variable "virtual_network_subnet_name" {
  type        = string
  default     = "sn1-vnet-ldo-euw-uat-01"
  description = "The subnet the VM should be put in"
}

variable "private_virtual_network_with_public_ip" {
  type        = bool
  default     = true
  description = "Determines whether packer should attempt public IP communication"
}

####################################################################################################################

// Begins Packer build Section
source "azure-arm" "build" {

  client_id                 = var.client_id
  client_secret             = var.client_secret
  subscription_id           = var.subscription_id
  tenant_id                 = var.tenant_id
  build_resource_group_name = var.gallery_rg_name

  // The sku you want to base your image off - In this case - Ubuntu 22
  os_type                 = "Windows"
  image_publisher         = "MicrosoftWindowsDesktop"
  image_offer             = "Windows-10"
  image_sku               = "21h1-evd-o365pp-g2" # Office 365 Windows 10 Multi-Session
  vm_size                 = "Standard_D4s_v4"
  winrm_insecure                         = "true"
  winrm_use_ssl                          = "true"
  winrm_username                         = "packer"

  virtual_network_name                   = var.virtual_network_name
  virtual_network_resource_group_name    = var.virtual_network_resource_group_name
  virtual_network_subnet_name            = var.virtual_network_subnet_name
  private_virtual_network_with_public_ip = var.private_virtual_network_with_public_ip

  // Name of Image which is created by Terraform
  managed_image_name                = "ldo-avd-windows-10"
  managed_image_resource_group_name = var.gallery_rg_name

  // Shared image gallery is created by terraform in the pre-req step, as is the resource group.
  shared_image_gallery_destination {
    gallery_name   = var.gallery_name
    image_name     = "ldo-avd-windows-10"
    image_version  = local.image_version
    resource_group = var.gallery_rg_name
    subscription   = var.subscription_id
    replication_regions = [
      "northeurope"
    ]
  }
}

# a build block invokes sources and runs provisioning steps on them. The
# documentation for build blocks can be found here:
# https://www.packer.io/docs/templates/hcl_templates/blocks/build
build {
  sources = ["source.azure-arm.vhd"]

  provisioner "powershell" {
    inline = ["New-Item -Path ${var.image_folder} -ItemType Directory -Force"]
  }

  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "${path.root}/scripts/ImageHelpers"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/scripts/SoftwareReport"
  }

  provisioner "file" {
    destination = "${var.image_folder}/SoftwareReport/"
    source      = "${path.root}/../../helpers/software-report-base"
  }

  provisioner "file" {
    destination = "C:/"
    source      = "${path.root}/post-generation"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    source      = "${path.root}/scripts/Tests"
  }

  provisioner "file" {
    destination = "${var.image_folder}\\toolset.json"
    source      = "${path.root}/toolsets/toolset-2019.json"
  }

  provisioner "windows-shell" {
    inline = [
      "net user ${var.install_user} ${var.install_password} /add /passwordchg:no /passwordreq:yes /active:yes /Y",
      "net localgroup Administrators ${var.install_user} /add",
      "winrm set winrm/config/service/auth @{Basic=\"true\"}",
      "winrm get winrm/config/service/auth"
    ]
  }

  provisioner "powershell" {
    inline = ["if (-not ((net localgroup Administrators) -contains '${var.install_user}')) { exit 1 }"]
  }

  provisioner "powershell" {
    elevated_password = "${var.install_password}"
    elevated_user     = "${var.install_user}"
    inline            = ["bcdedit.exe /set TESTSIGNING ON"]
  }

  provisioner "powershell" {
    environment_vars = [
      "IMAGE_VERSION=${local.image_version}",
      "IMAGE_OS=${local.image_os}",
      "AGENT_TOOLSDIRECTORY=${var.agent_tools_directory}",
      "IMAGEDATA_FILE=${var.imagedata_file}"
    ]
    execution_policy = "unrestricted"
    scripts          = [
      "${path.root}/scripts/Installers/Configure-Antivirus.ps1",
      "${path.root}/scripts/Installers/Install-PowerShellModules.ps1",
      "${path.root}/scripts/Installers/Install-WindowsFeatures.ps1",
      "${path.root}/scripts/Installers/Install-Choco.ps1",
      "${path.root}/scripts/Installers/Initialize-VM.ps1",
      "${path.root}/scripts/Installers/Update-ImageData.ps1",
      "${path.root}/scripts/Installers/Update-DotnetTLS.ps1"
    ]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    scripts = [
      "${path.root}/scripts/Installers/Install-VCRedist.ps1",
      "${path.root}/scripts/Installers/Install-Docker.ps1",
      "${path.root}/scripts/Installers/Install-PowershellCore.ps1",
      "${path.root}/scripts/Installers/Install-WebPlatformInstaller.ps1"
    ]
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }
image_folder
  provisioner "powershell" {
    elevated_password = "${var.install_password}"
    elevated_user     = "${var.install_user}"
    scripts           = [
      "${path.root}/scripts/Installers/Install-VS.ps1",
      "${path.root}/scripts/Installers/Install-KubernetesTools.ps1",
      "${path.root}/scripts/Installers/Install-NET48.ps1"
    ]
    valid_exit_codes  = [0, 3010]
  }

  provisioner "powershell" {
    scripts = [
      "${path.root}/scripts/Installers/Install-Wix.ps1",
      "${path.root}/scripts/Installers/Install-WDK.ps1",
      "${path.root}/scripts/Installers/Install-Vsix.ps1",
      "${path.root}/scripts/Installers/Install-AzureCli.ps1",
      "${path.root}/scripts/Installers/Install-AzureDevOpsCli.ps1",
      "${path.root}/scripts/Installers/Install-CommonUtils.ps1",
      "${path.root}/scripts/Installers/Install-JavaTools.ps1",
      "${path.root}/scripts/Installers/Install-Kotlin.ps1",
      "${path.root}/scripts/Installers/Install-OpenSSL.ps1"
    ]
  }

  provisioner "powershell" {
    execution_policy = "remotesigned"
    scripts          = ["${path.root}/scripts/Installers/Install-ServiceFabricSDK.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }

  provisioner "windows-shell" {
    inline = ["wmic product where \"name like '%%microsoft azure powershell%%'\" call uninstall /nointeractive"]
  }

  provisioner "powershell" {
    scripts = [
      "${path.root}/scripts/Installers/Install-Ruby.ps1",
      "${path.root}/scripts/Installers/Install-PyPy.ps1",
      "${path.root}/scripts/Installers/Install-Toolset.ps1",
      "${path.root}/scripts/Installers/Configure-Toolset.ps1",
      "${path.root}/scripts/Installers/Install-NodeLts.ps1",
      "${path.root}/scripts/Installers/Install-AndroidSDK.ps1",
      "${path.root}/scripts/Installers/Install-AzureModules.ps1",
      "${path.root}/scripts/Installers/Install-Pipx.ps1",
      "${path.root}/scripts/Installers/Install-PipxPackages.ps1",
      "${path.root}/scripts/Installers/Install-Git.ps1",
      "${path.root}/scripts/Installers/Install-GitHub-CLI.ps1",
      "${path.root}/scripts/Installers/Install-PHP.ps1",
      "${path.root}/scripts/Installers/Install-Rust.ps1",
      "${path.root}/scripts/Installers/Install-Sbt.ps1",
      "${path.root}/scripts/Installers/Install-Chrome.ps1",
      "${path.root}/scripts/Installers/Install-Edge.ps1",
      "${path.root}/scripts/Installers/Install-Firefox.ps1",
      "${path.root}/scripts/Installers/Install-Selenium.ps1",
      "${path.root}/scripts/Installers/Install-IEWebDriver.ps1",
      "${path.root}/scripts/Installers/Install-Apache.ps1",
      "${path.root}/scripts/Installers/Install-Nginx.ps1",
      "${path.root}/scripts/Installers/Install-Msys2.ps1",
      "${path.root}/scripts/Installers/Install-WinAppDriver.ps1",
      "${path.root}/scripts/Installers/Install-R.ps1",
      "${path.root}/scripts/Installers/Install-AWS.ps1",
      "${path.root}/scripts/Installers/Install-DACFx.ps1",
      "${path.root}/scripts/Installers/Install-MysqlCli.ps1",
      "${path.root}/scripts/Installers/Install-SQLPowerShellTools.ps1",
      "${path.root}/scripts/Installers/Install-SQLOLEDBDriver.ps1",
      "${path.root}/scripts/Installers/Install-DotnetSDK.ps1",
      "${path.root}/scripts/Installers/Install-Mingw64.ps1",
      "${path.root}/scripts/Installers/Install-Haskell.ps1",
      "${path.root}/scripts/Installers/Install-Stack.ps1",
      "${path.root}/scripts/Installers/Install-Miniconda.ps1",
      "${path.root}/scripts/Installers/Install-AzureCosmosDbEmulator.ps1",
      "${path.root}/scripts/Installers/Install-Mercurial.ps1",
      "${path.root}/scripts/Installers/Install-Zstd.ps1",
      "${path.root}/scripts/Installers/Install-NSIS.ps1",
      "${path.root}/scripts/Installers/Install-CloudFoundryCli.ps1",
      "${path.root}/scripts/Installers/Install-Vcpkg.ps1",
      "${path.root}/scripts/Installers/Install-PostgreSQL.ps1",
      "${path.root}/scripts/Installers/Install-Bazel.ps1",
      "${path.root}/scripts/Installers/Install-AliyunCli.ps1",
      "${path.root}/scripts/Installers/Install-RootCA.ps1",
      "${path.root}/scripts/Installers/Install-MongoDB.ps1",
      "${path.root}/scripts/Installers/Install-GoogleCloudSDK.ps1",
      "${path.root}/scripts/Installers/Install-CodeQLBundle.ps1",
      "${path.root}/scripts/Installers/Install-BizTalkBuildComponent.ps1",
      "${path.root}/scripts/Installers/Disable-JITDebugger.ps1",
      "${path.root}/scripts/Installers/Configure-DynamicPort.ps1",
      "${path.root}/scripts/Installers/Configure-GDIProcessHandleQuota.ps1",
      "${path.root}/scripts/Installers/Configure-Shell.ps1",
      "${path.root}/scripts/Installers/Enable-DeveloperMode.ps1",
      "${path.root}/scripts/Installers/Install-LLVM.ps1"
    ]
  }

  provisioner "powershell" {
    elevated_password = "${var.install_password}"
    elevated_user     = "${var.install_user}"
    scripts           = ["${path.root}/scripts/Installers/Install-WindowsUpdates.ps1"]
  }

  provisioner "windows-restart" {
    check_registry        = true
    restart_check_command = "powershell -command \"& {if ((-not (Get-Process TiWorker.exe -ErrorAction SilentlyContinue)) -and (-not [System.Environment]::HasShutdownStarted) ) { Write-Output 'Restart complete' }}\""
    restart_timeout       = "30m"
  }

  provisioner "powershell" {
    pause_before = "2m0s"
    scripts      = [
      "${path.root}/scripts/Installers/Wait-WindowsUpdatesForInstall.ps1",
      "${path.root}/scripts/Tests/RunAll-Tests.ps1"
    ]
  }

  provisioner "powershell" {
    inline = ["if (-not (Test-Path ${var.image_folder}\\Tests\\testResults.xml)) { throw '${var.image_folder}\\Tests\\testResults.xml not found' }"]
  }

  provisioner "powershell" {
    environment_vars = ["IMAGE_VERSION=${local.image_version}"]
    inline           = ["pwsh -File '${var.image_folder}\\SoftwareReport\\SoftwareReport.Generator.ps1'"]
  }

  provisioner "powershell" {
    inline = [
      "if (-not (Test-Path C:\\software-report.md)) { throw 'C:\\software-report.md not found' }",
      "if (-not (Test-Path C:\\software-report.json)) { throw 'C:\\software-report.json not found' }"
    ]
  }

  provisioner "file" {
    destination = "${path.root}/Windows10-Readme.md"
    direction   = "download"
    source      = "C:\\software-report.md"
  }

  provisioner "file" {
    destination = "${path.root}/software-report.json"
    direction   = "download"
    source      = "C:\\software-report.json"
  }

  provisioner "powershell" {
    environment_vars = ["INSTALL_USER=${var.install_user}"]
    scripts          = [
      "${path.root}/scripts/Installers/Run-NGen.ps1",
      "${path.root}/scripts/Installers/Finalize-VM.ps1"
    ]
    skip_clean       = true
  }

  provisioner "windows-restart" {
    restart_timeout = "10m"
  }

  provisioner "powershell" {
    inline = [
      "if( Test-Path $Env:SystemRoot\\System32\\Sysprep\\unattend.xml ){ rm $Env:SystemRoot\\System32\\Sysprep\\unattend.xml -Force}",
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
      "while($true) { $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $imageState.ImageState; Start-Sleep -s 10  } else { break } }"]
  }
}
