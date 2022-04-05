# Citrix Status Email Report Script
# Version 1.2 - In Progress - 4 Dec 2019
#
# Joshua Frederici

#####################################################################################################
#
# Basic Program Flow
#
# 1) Get list of Citrix sites and Delivery Controllers
# 2) Loop through Delivery Controllers... 
#     2a) Get a list of Citrix machines
#     2b) Get interesting event log entries and build the 2nd half of the report as we go.
# 3) Filter and report on Citrix machines that meet our criteria.
#     3a) Report on Delivery Contollers we could get data fron.
#     3b) Build tables of machines to report on.
# 4) Assemble and send email report
#
#####################################################################################################

# Add Citrix snapins
Add-PSSnapin Citrix.Broker.Admin.V2

#####################################################################################################
# Update recipient list as necessary
$Recipients = @("recipient@domain.org")
$RecipientsCC = @("ccrecipient@domain.org")
$FromAddress = "NoReply-CitrixReports@domain.org"
$EmailSubjet = "Daily Citrix Report"
$SMTPServer = "mail.domain.org"
#####################################################################################################

#####################################################################################################
# Update path to CSV file containing list of Delivery Controllers
# DEBUG: $DeliveryControllerList = Import-CSV C:\Support\Servers.csv

# Prod
# $DeliveryControllerList = Import-CSV D:\Scripts\CitrixReport\Servers.csv
# Testing
$DeliveryControllerList = Import-CSV D:\Scripts\CitrixReport\Servers-Pre.csv
#####################################################################################################


# set / initialize variables
# $ErrorActionPreference = "SilentlyContinue"
$CitrixMachines = $null
$CitrixServers = $null
$Body = $null
$BodyCitrix = $null
$BodyEvents = $null
$BodyEvents2 = $null
$OfflineController = New-Object System.Collections.Generic.List[System.Object]
$OfflineEventLogs = New-Object System.Collections.Generic.List[System.Object]

# Get today's date and yesterday's date
$today = [DateTime]::Today
$yesterday = $today.AddDays(-1)

# set body for HTML email output
$bodyCitrix=@"
<style>
@charset "UTF-8";

table
{
font-family:"Trebuchet MS", Arial, Helvetica, sans-serif;
border-collapse:collapse;
}
td 
{
font-size:1em;
border:1px solid #000000;
padding:5px 5px 5px 5px;
}
th 
{
border:1px solid #000000;
padding:5px 5px 5px 5px;
font-size:1.1em;
text-align:center;
padding-top:5px;
padding-bottom:5px;
padding-right:7px;
padding-left:7px;
background-color:#ffffff;
color:#000000;
}
name tr
{
color:#F00000;
background-color:#ffffff;
}
</style>
"@

$BodyEvents =@"
<style>
@charset "UTF-8";

table
{
font-family:"Trebuchet MS", Arial, Helvetica, sans-serif;
border-collapse:collapse;
}
td 
{
font-size:1em;
border:1px solid #000000;
padding:5px 5px 5px 5px;
}
th 
{
border:1px solid #000000;
padding:5px 5px 5px 5px;
font-size:1.1em;
text-align:center;
padding-top:5px;
padding-bottom:5px;
padding-right:7px;
padding-left:7px;
background-color:#ffffff;
color:#000000;
}
name tr
{
color:#F00000;
background-color:#ffffff;
}
</style>
"@

$BodyEvents += "<BR><BR><BR><H3>Event Log Search:</H3>The information below is information for the Citrix Team only.  Please do not call out on it."

# Take list of Citrix Delivery Controllers and query for list of all machines (including desktops).
# Query primary and secondary controllers, making note of any that do not respond.

Foreach ($Server in $DeliveryControllerList)
{
    $SiteName = $Server.SiteName
    $Primary = $Server.Primary
    $Secondary = $Server.Secondary

    $GetMachine = $null
    $SortedEvents = $null

    # $secondaryFailed: 0 = tried, 1 = failed, 2 = not tried
    $SecondaryFailed=2
    
    # Get Citrix machine list
    Write-Host "Getting Citrix machine list from $Primary"
    try
    {
        # Get list of machines from Primary Delivery Controller
        $GetMachine = Get-BrokerMachine -AdminAddress $Primary -MaxRecordCount 10000
    }
    catch
    {
        # The Primary failed... log it for the report...
        Write-Warning "Could not connect to Delivery Controller $Primary!"
        $OfflineController.Add($Primary)

        # ... and try the secondary
        try
        {
            $SecondaryFailed = 0
            Write-Host "Getting Citrix machine list from $Secondary"
            $GetMachine = Get-BrokerMachine -AdminAddress $Secondary -MaxRecordCount 10000
        }
        catch
        {
            # The secondary failed... log it for thr report.
            $SecondaryFailed = 1
            Write-Warning "Could not connect to Delivery Controller $Secondary!"
            $OfflineController.Add($Secondary)
        }
        finally
        {


        }
    }
    finally
    {
        # The primary controller responded, but test the secondary anyway just to see if it's up but don't do anything with the data it returns.
        if ($SecondaryFailed -eq 2)
        {
            try
            {
                # Querying the primary controller succeeded, so test the secondary also but dump the data it returned.
                Write-Host "Successfully queried $Primary, testing $Secondary"
                $blah = Get-BrokerMachine -AdminAddress $Secondary -MaxRecordCount 10000
            }
            catch
            {
                $SecondaryFailed = 1
                Write-Warning "Could not connect to Delivery Controller $Secondary!"
                $OfflineController.Add($Secondary)
            }
        }
    }

    # If data was returned...
    if ($GetMachine -ne $null)
    {
        # ... add it to the running list of Citrix machines...
        $CitrixMachines += $GetMachine
    }


    # Get Delivery Controller event logs

    # Initialize array, see: https://gallery.technet.microsoft.com/scriptcenter/An-Array-of-PowerShell-069c30aa
    $events = @()

    # get 1200-1201 events from the primary and secondary Delivery Controllers
    # TODO: add error checking here!
    Write-Host "Getting event logs from server $Primary"
    try
    {
        $events += Get-WinEvent -ComputerName $Primary -FilterHashTable @{logname="Application"; ProviderName="Citrix Broker Service"; id=1200,1201; StartTime=$yesterday; EndTime=$today} -ErrorAction Stop
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogException]
    {
        Write-Warning "Failed to get logs from $Primary"
        $OfflineEventLogs.Add($Primary)
    }
    catch [System.Exception]
    {
        if ($_.Exception -match "No events were found that match the specified selection criteria.")
        {
            Write-Host "No matching event logs found on $Primary"
        }
    }
    finally
    {
        #Write-Host "Moving on...."
    }

    # Get event logs from Secondary Delivery Controller
    Write-Host "Getting event logs from server $Secondary"
    try
    {
        $events += Get-WinEvent -ComputerName $Secondary -FilterHashTable @{logname="Application"; ProviderName="Citrix Broker Service"; id=1200,1201; StartTime=$yesterday; EndTime=$today} -ErrorAction Stop
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogException]
    {
        Write-Warning "Failed to get logs from $Secondary"
        $OfflineEventLogs.Add($Secondary)
    }
    catch [System.Exception]
    {
        if ($_.Exception -match "No events were found that match the specified selection criteria.")
        {
            Write-Host "No matching event logs found on $Secondary"
        }
    }
    finally
    {
        #Write-Host "Moving on...."
    }
    
    # select properties and sort the events that are returned
    $SortedEvents = $events | Select-Object TimeCreated, MachineName, Id, LevelDisplayName, Message | Sort-Object TimeCreated -Descending
    
    # convert event list to HTML and add to email body
    If ($SortedEvents -ne $null)
    {
        $bodyEvents2 += $SortedEvents | ConvertTo-HTML -PreContent "<H4>$SiteName`:</H4>"
    }
    else
    {
        $bodyEvents2 += "<H4>$SiteName`:</H4> No database connectivity issues found."
    }
    Write-Host
}


# Report on Delivery Controllers that we couldn't get info back from

# Format the list of failed Delivery Controllers for the HTML report.
$OfflineControllerList = $OfflineController -join "<BR />"
$OfflineEventLogsList = $OfflineEventLogs -join "<BR />"

# List failed controllers in email body
if ($OfflineController -ne $null)
{
    $BodyCitrix += "<B>Could not connect to the following Delivery Controller servers:</B><BR> $OfflineControllerList"
}


# List failed controllers in email body
if ($OfflineEventLogs -ne $null)
{
    $BodyEvents += "<B>Could not connect to the following Delivery Controller servers:</B><BR> $OfflineEventLogsList"
}




# Now sort through all the Citrix machines that were returned and look for ones that we want to report on.

# Filter out everything except servers, filter out Image Maintenance servers
#Testing: $CitrixServers = $CitrixMachines | Where-Object {$_.DeliveryType -eq "DesktopsAndApps" -and $_.SessionSupport -eq "MultiSession" -and $_.DesktopGroupName -Like "*Maintenance*"}
#Production: $CitrixServers = $CitrixMachines | Where-Object {$_.DeliveryType -eq "DesktopsAndApps" -and $_.SessionSupport -eq "MultiSession" -and $_.DesktopGroupName -NotLike "*Maintenance*"}
# Debug: 
$CitrixServers = $CitrixMachines | Where-Object {$_.DeliveryType -eq "DesktopsAndApps" -and $_.SessionSupport -eq "MultiSession" -and $_.DesktopGroupName -Like "*Maintenance*"}

# Filter list of servers to show those that are off or unregistered
# If any are found, include them in the email body; if none are found report that none are found.
$OfforUnreg = $CitrixServers | Where-Object {($_.PowerState -eq "Off" -or $_.RegistrationState -eq "Unregistered") -and $_.InMaintenanceMode -ne "True"} | Select-Object DNSName, InMaintenanceMode, PowerState, RegistrationState
#$OfforUnreg = $CitrixServers | Where-Object {($_.PowerState -eq "Off" -or $_.RegistrationState -eq "Unregistered")} | select DNSName, InMaintenanceMode, PowerState, RegistrationState

if ($OfforUnreg -ne $null)
{
    $BodyCitrix += $OfforUnreg | ConvertTo-Html -PreContent "<H3>Off or Unregistered Machines</H3>" | Out-String
}
Else
{
    $BodyCitirx += "<H3>Off or Unregistered Machines</H3> No servers off or unregistered."
}



# Filter list of servers to show those that are in maintenance mode or unknown power state
# If any are found, include them in the email body; if none are found report that none are found.

$MMorUnknown = $CitrixServers | Where-Object {$_.PowerState -eq "Unknown" -or $_.InMaintenanceMode -eq "True"} | Select-Object DNSName, InMaintenanceMode, PowerState, RegistrationState

if ($MMorUnknown -ne $null)
{
    $BodyCitrix += $MMorUnknown | ConvertTo-Html -PreContent "<H3>Maintenance Mode or Unknown Power State</H3>" | Out-String
}
Else
{
    $BodyCitrix += "<H3>Maintenance Mode or Unknown Power State</H3> No servers are in maintenance mode or unknown power state."
}

$body += $BodyCitrix + $BodyEvents + $BodyEvents2

Write-Host
Write-Host "Sending email"

# Send email and end
Send-MailMessage -to $Recipients -Cc $RecipientsCC -from $FromAddress -Subject $EmailSubjet -body $body -BodyAsHtml -SmtpServer $SMTPServer