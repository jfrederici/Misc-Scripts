<#
********************************************************************************
AWSPowerControl.ps1

By: Joshua Frederici
Created: 19 April 2016

Borrowed from some random guy's blog and edited extensively.
Reference: http://thesysadminswatercooler.blogspot.com/2014/09/aws-start-and-stop-ec2-instances-on.html

Script is used to automatically start and stop AWS instances based upon tag
value.

Tag must be named "PowerSchedule" and in format of H:H:D-D (Start Hour: Stop
Hour: Schedule Start Day - Schedule Stop Day (0=Sunday, 6=Saturday).

Script can accomodate overnight runs (ex: 20:5:0-4) and weekend runs (ex: 
9:17:5-2).

NOTE: Requires AWSPowerShell module.

********************************************************************************
#>

Initialize-awsdefaults

Import-Module AWSPowerShell

# Initialize logging
$LogFile = 'C:\Support\AWSPowerControl\'+(Get-Date -Format "yyyy-MM-dd")+".log"
Function LogWrite
{
    Param ([string]$logstring)

    $LogTime = Get-Date -UFormat %Y-%m-%d*%T
    Add-Content $LogFile -value ($LogTime + ': ' + $logstring)
}
Add-Content $LogFile -value ("********************************************************************************")
LogWrite ("Script Running!")

#Create arrays
$instanceStart = @()
$instanceStop = @()

#$fromEmail = "youremail@domain.com"
#$Recipients  = "toemail@domain.com"
#$emailserver = "emailserver"

#create filter to limit search on instances only
$filter_instances = New-Object amazon.EC2.Model.Filter
$filter_instances.Name = "resource-type"
$filter_instances.Value = "instance"

#create filter based on tag=PowerSchedule
$filter_tag = New-Object amazon.EC2.Model.Filter
$filter_tag.Name = "tag:PowerSchedule"
$filter_tag.Value = "*"

#join the two filters together
$filter = @($filter_instances, $filter_tag)

#retrieve the instances based on the filter parameters
$instances = Get-EC2Tag -Filter $filter

#set now date and day of week
$now = Get-Date
$dow = Get-Date -UFormat %u

#cycle through each instance found
foreach($instance in $instances)
{
    # debug
    LogWrite ("Evaluating instance: "+ $instance.resourceid)

    #reset variable to false for each instance through loop
    $startstopInstance = $false
   
    #Get current instance state,  either Running or Stopped
    $state = Get-EC2InstanceStatus -InstanceIds $instance.ResourceId
    $state = $state.InstanceState.Name
   
   #get schedule value
    $schedule = $instance.Value
    $schedule = $schedule.ToLower()
    if ($schedule -eq "disabled")
    {
        #if disabled then do nothing!
        Write-Host "Disabled schedule"
    }
    else
    {
        
        #Get Schedule from instance Tag Value, parse the values
        $schedule = $instance.Value -split ':'
        $start = [INT]$schedule[0]
        $stop = [INT]$schedule[1]
        $days = $schedule[2]
       
        #check if multiple days are set to run machine
        if ($days.Length -gt 1)
        {
            $days = $days -split '-'

        }
        
        #LogWrite ('DEBUG: ' + 'StartHour:' + $schedule[0] + ', StopHour:' + $schedule[1] + ', Days0:' + $days[0] + ', Days1:' + $days[1])

        # if machine runs overnight (i.e. stop is less than start), increment days[1] so that we can catch and 
        # shut machine down the next day, BUT ONLY FOR STOPPING IT (do not START it on that next day!)
        if ($stop -lt $start)
        {
            #LogWrite ('DEBUG: Overnight condition met, incrementing Days[1]')
            $days[1] = [int16]$days[1] + 1
            #LogWrite ('DEBUG: Days[1] = ' + $Days[1])

            if ($days[1] -eq 7)
            {
                $days[1] = 0
            }

            if ($dow -eq $days[1] -and $now.hour -eq $stop)
            {
                
                $startstopInstance = $true
            }
        }

        # check if the START/STOP range spans the weekend...
        if ($days[1] -lt $days[0])
        {
            #check if we are between the START day and Saturday, OR if we are between Sunday and STOP day
            if (($dow -ge $days[0] -and $dow -le 6) -or ($dow -ge 0 -and $dow -le $days[1]))
            {
                $startstopInstance = $true
            }
        }
        else
        {
            # Normal run (not wekend)
            #check if current day is between scheduled days, if so set variable to True
            if($dow -ge $days[0] -and $dow -le $days[1])
            {
                $startstopInstance = $true
            }
        }


        if ($startstopInstance -eq $true)
        {

            if ($now.Hour -eq $start -and $state -ne "running")
            {
                Start-EC2Instance -InstanceIds $instance.ResourceId
                #write-host "Starting Instance " $instance.ResourceId
                LogWrite ("Starting Instance: " + $instance.ResourceId)
            }

            if ($now.Hour -eq $stop -and $state -eq "running")
            {
                Stop-EC2Instance -Instance $instance.ResourceId
                #write-host "Stopping Instance " $instance.ResourceId
                LogWrite ("Stopping Instance: " + $instance.ResourceId)
            }
        }
    }
}

LogWrite ("Script Complete!")
Add-Content $LogFile -value ("********************************************************************************")

# The End!