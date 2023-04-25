# Builds an Azure compute gallery
module "gallery" {
  source = "registry.terraform.io/libre-devops/compute-gallery/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  gallery_name = "gal${var.short}${var.loc}${terraform.workspace}01"
  description  = "A Compute Gallery to host the Azure DevOps agent image"
}

# Pre-defines an image for the packer
module "image" {
  source = "registry.terraform.io/libre-devops/shared-image/azurerm"

  rg_name  = module.rg.rg_name
  location = module.rg.rg_location
  tags     = module.rg.rg_tags

  images = {
    "ldo-avd-win-10" = {
      gallery_name             = module.gallery.gallery_name
      is_image_specialised     = false
      image_hyper_v_generation = "V2"
      image_os_type            = "Windows"

      identifier = {
        publisher = "Libre-DevOps"
        offer     = "avd-windows"
        sku       = "10"
      }
    },
  }
}
