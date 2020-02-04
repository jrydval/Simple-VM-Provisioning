# Simple-VM-Provisioning
 Simple VMware ESX provisioning script using PowerShell and PowerCLI creating VMs, vSwitches, PortGroups, uploading ISO files and mounting them and starting the new VMs.

 ## Configuration
 Config files are `VM List.csv` and `Switch List.csv`. The format is more-less self describing.
 Some folders and names - like datastore name and folder names - are defined in the script in Configuration section-

 ## Usage
 - Install PowerShelll (tested with PowerShell v7rc2 on MacOS)
 - Install PowerCLI by running `Install-Module VMware.PowerCLI` from PowerShell
 - Modify the config files
 - Modify the config section of the script if needed
 - Start the script

 ## Sample output
 Sample run is in the file `docs/sample run output.txt`

