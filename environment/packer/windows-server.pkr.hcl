# environment/packer/windows-server.pkr.hcl
#
# Builds a Hyper-V Windows Server 2022 VM with the full Phase 1/1.5 toolchain
# baked in: JDK, Ghidra, GhidrAssist, GhidrAssistMCP (enabled, no manual GUI
# step), and Claude Code. Values come from environment/config.ps1 — see
# environment/packer/README.md for how the two stay in sync and how to run
# this (needs an elevated shell with Hyper-V rights).

packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = ">= 1.1.0"
    }
  }
}

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "vm_name" {
  type = string
}

variable "switch_name" {
  type = string
}

variable "cpus" {
  type = number
}

variable "memory_mb" {
  type = number
}

variable "disk_size_mb" {
  type = number
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "output_directory" {
  type = string
}

source "hyperv-iso" "fdny_decomp" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum
  vm_name      = var.vm_name
  switch_name  = var.switch_name
  cpus         = var.cpus
  memory       = var.memory_mb
  disk_size    = var.disk_size_mb
  # Generation 1 (not 2): attaching autounattend.xml via cd_files needs an
  # external ISO-creation tool (oscdimg/mkisofs/etc.) that isn't installed
  # here. Gen1 supports a virtual floppy, which Packer builds natively with
  # no external dependency — Windows Setup scans a floppy root for
  # autounattend.xml the same way it scans a CD root.
  generation = 1
  # Hyper-V's VMMS service needs to set NTFS ACLs on the ISO/VHDs it
  # attaches — a cloud-sync drive (this repo lives on Google Drive) can't
  # support that ("Access is denied" / "parameter is incorrect" from
  # Add-VMDvdDrive). Build artifacts have to live on a real local volume.
  output_directory = var.output_directory
  floppy_files     = ["./http/autounattend.xml"]
  boot_wait        = "0s"
  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer shutdown\""
  shutdown_timeout = "15m"

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "6h" # first boot + unattended install can take a while
}

build {
  sources = ["source.hyperv-iso.fdny_decomp"]

  provisioner "file" {
    source      = "../config.ps1"
    destination = "C:/fdny-decomp/environment/config.ps1"
  }

  provisioner "file" {
    source      = "../../plan.md"
    destination = "C:/fdny-decomp/plan.md"
  }

  provisioner "file" {
    source      = "../../CLAUDE.md"
    destination = "C:/fdny-decomp/CLAUDE.md"
  }

  provisioner "file" {
    source      = "../../RESEARCH.md"
    destination = "C:/fdny-decomp/RESEARCH.md"
  }

  provisioner "file" {
    # Needed before provision.ps1's `git init` — without it, `git add -A`
    # would stage the entire Ghidra/JDK/etc install (multiple GB).
    source      = "../../.gitignore"
    destination = "C:/fdny-decomp/.gitignore"
  }

  provisioner "file" {
    source      = "../../SETUP_NOTES.md"
    destination = "C:/fdny-decomp/SETUP_NOTES.md"
  }

  provisioner "file" {
    # Trailing slash on source: copies scripts/*, not scripts/ itself, into
    # destination — omitting it nests as environment/scripts/scripts/*.ps1.
    source      = "../scripts/"
    destination = "C:/fdny-decomp/environment/scripts"
  }

  provisioner "powershell" {
    script = "./scripts/provision.ps1"
  }
}
