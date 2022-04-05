####################################################################################################
# Citrix Power Up Script
# Version 1.0 - 9 Dec 2019
#
# Joshua Frederici
#
# Description:
# Script looks for Citrix servers that are powered off but shouldn't be and powers them up.
#
# Requirements:
# VMware PowerCLI
# Citrix Virtual Apps and Desktops PowerShell module
#
####################################################################################################
#
# Basic Program Flow
#
# 1) Read CSV file containing Citrix site info (delivery controllers and vCenter server info)
# 2) Loop through Citrix sites and pull machine list
#       a) try primary controller first, then secondary if error on primary
# 3) Look at machines returned looking for servers that are powered off, not in maintenance mode, 
#       and not in Image Maintenance delivery group.
# 4) If matching servers found, connect to appropriate vCenter server and power them up.
#
####################################################################################################

####################################################################################################
# Update path to CSV file containing list of Delivery Controllers
$DeliveryControllerList = Import-CSV D:\Scripts\CitrixReport\Servers.csv
#
# CSV file should have the following columns with the following headers:
# SiteName, Primary, Secondary, vCenter
#
# Sitename - name of the Citrix site.  Not used in this script but used in the daily report script.
# Primary / Secondary - FQDN's of the delivery controller servers to be queried for each site.
# vCenter - FQDN of the vCenter server associated with the Citrix site.
#
# Note: script does NOT have embedded vCenter credentials and will prompt for credentials on run.
# Credentials can be saved in the locale credential store by manually connecting the first time
# using the Connect-VIServer PowerCLI cmdlet with the SaveCredentials parameter.
#
####################################################################################################

# Add Citrix snapin
Add-PSSnapin Citrix.Broker.Admin.V2

# set / initialize variables
# $ErrorActionPreference = "SilentlyContinue"
$CitrixServers = $null

# Take list of Citrix Delivery Controllers and query for list of all machines (including desktops).
# Query primary and secondary controllers, making note of any that do not respond.

foreach ($CitrixSite in $DeliveryControllerList) {
    $MachineList = $null

    # read primary and secondary controllers and vCenter server from 
    $Primary = $CitrixSite.Primary
    $Secondary = $CitrixSite.Secondary
    $vCenter = $CitrixSite.vCenter
    
    # Get Citrix machine list
    Write-Host "Getting Citrix machine list from $Primary"
    try {
        # Get list of machines from Primary Delivery Controller
        $MachineList = Get-BrokerMachine -AdminAddress $Primary -MaxRecordCount 10000
    }
    catch {
        # The Primary failed... 
        Write-Warning "Could not connect to Delivery Controller $Primary!"

        # ... try the secondary
        try {
            Write-Host "Getting Citrix machine list from $Secondary"
            $MachineList = Get-BrokerMachine -AdminAddress $Secondary -MaxRecordCount 10000
        }
        catch {
            # The secondary failed also...
            Write-Warning "Could not connect to Delivery Controller $Secondary!"
        }
        finally {

        }
    }

    # If data was returned...
    if ($MachineList -ne $null) {

        $CitrixServers = $MachineList | Where-Object { $_.DeliveryType -eq "DesktopsAndApps" -and $_.SessionSupport -eq "MultiSession" -and $_.InMaintenanceMode -eq $false -and $_.DesktopGroupName -Like "*Maintenance*" }
        $OffServers = $CitrixServers | Where-Object { $_.PowerState -eq "Off" } | Select-Object DNSName, InMaintenanceMode, PowerState, RegistrationState
        
        # If there's a server to power on then connect to vCenter
        if ($OffServers -ne $null) {
            Write-Host "Connecting to vCenter server: $vCenter"
            ################################################################################################################
            ## Replace 'Domain\ServiceAccount with the service account with rights to perform power opertions in vCenter
            ################################################################################################################
            $VIServer = Connect-ViServer -Server $vCenter -User Domain\ServiceAccount    
                
            # loop through powered off machines and power them up.
            foreach ($server in $OffServers) {
                $VM = $null
                $hostname = $null

                $hostname = $server.DNSName.split('.')[0]
                if ($hostname -like "*CTXAPP*") {
                    $VM = Get-VM -name $hostname
                    Write-Host "Debug: $VM / $hostname"
                    if ($VM.PowerState -eq "PoweredOff") {
                        Start-VM -VM $VM -RunAsync
                    }
                }
            }
        }
        else {
            Write-Host "No servers matching criteria found."
        }
    }
    # Done with this vCenter server so disconnect it
    if ($VIServer -ne $null) {
        Write-Host "Disconnecting from vCenter server: $VIserver.name"
        $VIServer = Disconnect-VIServer -server $VIServer -Force
    }
}