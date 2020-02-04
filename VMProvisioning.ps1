#################################################################
# VM PROVISIONING                                               #
# My first UBS (Ugly Big Script) written in PowerShell          #
# License: GPL                                                  #
# Disclaimer: As-Is, No-Warranty                                #
# Author: dz3jar, jan@rydv.al                                   #
#################################################################

Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
$ErrorActionPreference = 'Stop'

#################################################################
# CONNECT TO ESX                                                #
#################################################################

if (-Not $global:DefaultVIServer) {
    Write-Host "Not connected" -ForegroundColor Red
    $esxHost = Read-Host "Enter ESX's IP address or hostname"
    Connect-VIServer $esxHost
}

#################################################################
# CONFIGURATION SECTION                                         #
#################################################################

# Datastore name or comment-out for auto-configuration - 1st DS will be used
$datastore = Get-Datastore -Name "datastore1" 

# Local folder with needed ISO files or comment-out for ./files/
#$isoSourcePath = "/Volumes/Pulec/Latest/" 

# Datastore folder name with ISO files or comment-out for /ISO/
$isoFolderName = "_ISO" 


#################################################################
# AUTO-CONFIGURATION SECTION                                    #
#################################################################

if (-Not $isoSourcePath ) { $isoSourcePath = "./files/" } 
if (-Not $isoFolderName) { $isoFolderName = "ISO" }
if (-Not $datastore) { $datastore = (Get-Datastore)[0] }

#################################################################
# CREATE VIRTUAL SWITCHES                                       #
#################################################################

$neededSwitches = Import-Csv -Path './Switch List.csv'
$allSwitches = (Get-VirtualSwitch).Name

Write-Host "Already Created Switches:" -ForegroundColor Yellow
$existingSwitches = $allSwitches | Where-Object { $neededSwitches.Name -contains $_ }
if ($existingSwitches) { $existingSwitches } else { "none" }
Write-Host ""

Write-Host "Switches to be created:" -ForegroundColor Green
$missingSwitches = $neededSwitches.Name | Where-Object { $allSwitches -notcontains $_ }
if ($missingSwitches) { $missingSwitches } else { "none" } 
Write-Host ""

$missingSwitches | ForEach-Object {
    $creatingSwitch = $_
    Write-Host "Creating Switch: " $creatingSwitch -ForegroundColor Blue
    $param = $neededSwitches | Where-Object { $creatingSwitch -eq $_.Name }
    $param | Format-Table

    New-VirtualSwitch -Name $param.Name -Nic $param.NIC | Out-Null
    $newSwitch = Get-VirtualSwitch -Name $creatingSwitch -ErrorAction SilentlyContinue
    if ($newSwitch) { 
        if ($param.Mode -eq "sniffing") {
            $newSwitch | Get-SecurityPolicy | Set-SecurityPolicy -AllowPromiscuous $true -ForgedTransmits $true -MacChanges $true | Out-Null
            "Created sniffing"
        }
        else { 
            "Created" 
        }
        
    }
    else { "Not created!" }
    Write-Host ""
}


#################################################################
# CREATE PORT GROUPS                                            #
#################################################################

$allPortGroups = (Get-VirtualPortGroup).Name

Write-Host "Already Created PortGroups:" -ForegroundColor Yellow
$existingPortGroups = $allPortGroups | Where-Object { $neededSwitches.PortGroupName -contains $_ }
if ($existingPortGroups) { $existingPortGroups } else { "none" }
Write-Host ""

Write-Host "PortGroups to be created:" -ForegroundColor Green
$missingPortGroups = $neededSwitches.PortGroupName | Where-Object { $allPortGroups -notcontains $_ }
if ($missingPortGroups) { $missingPortGroups } else { "none" } 
Write-Host ""

$missingPortGroups | ForEach-Object {
    $creatingPortGroup = $_
    Write-Host "Creating PortGroup: " $creatingPortGroup -ForegroundColor Blue
    $param = $neededSwitches | Where-Object { $creatingPortGroup -eq $_.PortGroupName }
    $param | Format-Table
    if ($param.Mode -eq "Sniffing") { $vlanID = 4095 } else { $vlanID = 0 }

    New-VirtualPortGroup -Name $param.PortGroupName -VirtualSwitch $param.Name -VLanId $vlanID | Out-Null

    $newPortGroup = Get-VirtualPortGroup -Name $creatingPortGroup -ErrorAction SilentlyContinue
    if ($newPortGroup) { "Created" }  else { "Not created!" }
    Write-Host ""
}

#################################################################
# CREATE VIRTUAL MACHINES                                       #
#################################################################

$neededVMs = Import-Csv -Path './VM List.csv'
$allVMs = (Get-VM).Name

Write-Host "Already Created VMs:" -ForegroundColor Yellow
$existingVMs = $allVMs | Where-Object { $neededVMs.Name -contains $_ }
if ($existingVMs) { $existingVMs } else { "none" }
Write-Host ""

Write-Host "VMs to be created:" -ForegroundColor Green
$missingVMs = $neededVMs.Name | Where-Object { $allVMs -notcontains $_ }
if ($missingVMs) { $missingVMs } else { "none" } 
Write-Host ""

$missingVMs | ForEach-Object {
    $creatingVM = $_
    Write-Host "Creating VM: " $creatingVM -ForegroundColor Blue
    $param = $neededVMs | Where-Object { $creatingVM -eq $_.Name }
   
    $newVMparam = @{
        Name              = $creatingVM
        NumCpu            = $param.CPU
        DiskGB            = $param.Disk
        DiskStorageFormat = $param.Provisioning
        MemoryGB          = $param.Memory
        CD                = $true
        Datastore         = $datastore
        GuestId           = $param.OS
    }

    $newVMparam.Add("NetworkName", $param.Networks.Split("|"))

    New-VM @newVMparam | Format-Table -Property Name, NumCpu, MemoryGB

    $newVM = Get-VM -Name $creatingVM

    if ($param.Boot -eq "EFI") {
        "Setting EFI boot"
        $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $spec.Firmware = [VMware.Vim.GuestOsDescriptorFirmwareType]::efi
        $newVM.ExtensionData.ReconfigVM($spec)
        Write-Host ""
    }
}
Write-Host ""

#################################################################
# UPLOAD ISO IMAGES                                             #
#################################################################

$datastoreIsoPath = "vmstore:/$($datastore.Datacenter)/$($datastore.Name)/$isoFolderName"

Write-Host "Reading content of ${datastoreIsoPath} `n" -ForegroundColor Blue

if (-Not (Get-Item $datastoreIsoPath -ErrorAction SilentlyContinue) ) {
    Write-Host "Path $datastoreIsoPath does not exist, creating..." -ForegroundColor Green
    New-Item -Path $datastoreIsoPath
}

$ISOs = Get-ChildItem -Path $datastoreIsoPath
$neededISOs = $neededVMs.ISO | Select-Object -Unique

Write-Host "ISOs already in datastore:" -ForegroundColor Yellow
$existingISOs = $ISOs.Name | Where-Object { $neededISOs -contains $_ }
if ($existingISOs) { $existingISOs } else { "none" }
Write-Host ""

Write-Host "ISOs to be uploaded:" -ForegroundColor Green
$missingISOs = $neededISOs | Where-Object { $ISOs.Name -notcontains $_ }
$ISOsToUpload = $missingISOs | Select-Object -Unique
if ($ISOsToUpload) { $ISOsToUpload } else { "none" } 
Write-Host ""

$ISOsToUpload | ForEach-Object -Process {
    "Uploading $_"
    Copy-DatastoreItem "$isoSourcePath/$_" -Destination $datastoreIsoPath
} -End {
    Write-Host ""
}

#################################################################
# MOUNT  ISO IMAGES                                             #
#################################################################

$missingVMs | ForEach-Object -Begin {
    Write-Host "Mounting ISO images to new VM(s)" -ForegroundColor Green
} -Process {
    $mountingTo = $_
    $param = $neededVMs | Where-Object { $_.Name -eq $mountingTo }

    Write-Host "$($param.ISO) to $($param.Name)"

    $isoImage = (Get-Item "$datastoreIsoPath/$($param.ISO)").DatastoreFullPath
    Get-CDDrive $param.Name | Set-CDDrive -IsoPath $isoImage -StartConnected $true -Confirm:$false | Out-Null

} -End {
    Write-Host ""
}

#################################################################
# POWER-ON VIRTUAL MACHINES                                     #
#################################################################

$missingVMs | ForEach-Object -Begin {
    Write-Host "Starting new VM(s)" -ForegroundColor Green
} -Process {
    Write-Host $_
    Start-VM $_ | Out-Null
} -End {
    Write-Host "`nFinished" -ForegroundColor Blue
}
