function Check-SCCMBackups
{
	# $arrBackupFolders contains a list of locations that contain SCCM backups.
	$arrBackupFolders = "\\fileserver1\SCCMbackup`$","\\fileserver2\SCCMbackup","\\fileserver3\images\SCCMbackup"
	$dateYesterday = (Get-Date).addDays(-1)

	# Initialize variables
	$strSiteBackupNotRun = $null	# variable to hold list of sites whose backups did not run
	$strSiteBackupFailed = $null	# variable to hold list of sites whose backups ran but failes
	$boolTasksDidRun = 1			# initialized to 1; set to 0 if any backup task did not run
	$boolTasksRanSuccessfully = 1	# initialized to 1; set to 0 if any backup task did execute successfully

	Write-Host "Checking status of SCCM backup folders... " -nonewline
	# Loop through each value of $arrBackupFolders....
	ForEach ($strUNCPath in $arrBackupFolders)
	{
		# ... and get the directories it contains.
		$objBackupFolders = Get-ChildItem $strUNCPath | where {$_.PsIsContainer}
		# Loop through each discovered directory....
		ForEach ($objDirectory in $objBackupFolders)
		{
			# ... and check it directory was modified within the last day.
			if ($objDirectory.LastWriteTime -ge $dateYesterday)
			{
				# Task executed (we know because folder write time was updated)
				# Open log file and determine if job completed successfully.
				$strLogFilePath = $strUNCPath + "\" + $objDirectory.Name + "\" + $objDirectory.Name + "Backup\smsbkup.log"
				
				# Check smsbkup.log file modify time to ensure it was 
				# modified within the last 24 hours.
				$strLogFile = Get-Item $strLogFilePath
				If (!($strLogFile.LastWriteTime -ge $dateYesterday))
				{
					# File was NOT (!) modified in last 24 hours!
					# Since log file was not modified (something else must've written to the directory)....
					# Add Site Code (directory name) to the list of sites that did not run and set the flag...
					$strSiteBackupNotRun = $strSiteBackupNotRun + " " + $objDirectory.Name
					$boolTasksDidRun = 0
					# ...then stop processing this object and continue with the loop.
					Continue
				}
				
				# Line indicating success is four lines from the bottom of the file.
				$strLine = (Get-Content $strLogFilePath)[-4]
				
				# If the line doesnt match criteria, backup did not complete successfully.
				if ($strLine -notmatch "Backup task completed successfully with zero errors")
				{
					# Task ran but did not complete successfully
					# Add Site Code (directory name) to the list of failed backups....
					$strSiteBackupFailed = $strSiteBackupFailed + " " + $objDirectory.Name
					# ... and set the flag indicating that one or more tasks did not complete successfully.
					$boolTasksRanSuccessfully = 0
				}
			}
			else
			{
				# Task did not run as the directory modified date is not within last day.
				# Add Site Code (directory name) to the list of sites that did not run and set the flag
				$strSiteBackupNotRun = $strSiteBackupNotRun + " " + $objDirectory.Name
				$boolTasksDidRun = 0
			}
		}
	}
	Write-Host "Complete!" 

	# Check status of boolean flags and present data.
	if ($boolTasksDidRun -eq 0 -OR $boolTasksRanSuccessfully -eq 0)
	{
		# One or more tasks did not execute or failed during execution.
		if ($boolTasksDidRun -eq 0)
		{
			# One or more tasks did nto execute; list the site codes (directory names).
			Write-Host "Backup tasks for the following sites did not run: $strSiteBackupNotRun" -foregroundcolor red -backgroundcolor black
		}
		if ($boolTasksRanSuccessfully -eq 0)
		{
			# One or more tasks did not run successfully; list the site codes (directory names).
			Write-Host "Backup tasks for the following sites did not complete successfully: $strSiteBackupFailed" -foregroundcolor red -backgroundcolor black
		}
	}
	elseif ($boolTasksDidRun -eq 1 -AND $boolTasksRanSuccessfully -eq 1)
	{
		# All tasks completed successfully
		# (Directory modify dates are within 24 hours and all log files show last task execution was successful.)
		Write-Host "All SCCM backup tasks executed and ran successfully." -foregroundcolor green
	}
	Write-Host ""
}