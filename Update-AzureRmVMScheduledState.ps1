<#
Update-AzureRmVMScheduledState.ps1

Author: Dirk Dulfer
Version: 0.4
Original: 02 September 2018
Current: 27 May 2019

Set Azure VM power state or scale its size according a scheduled state pattern, declared using Azure Tags

Microsoft Azure offers a fast, flexible and easily scalable platform for hosting Virtual Machine workloads. However, this so called IaaS (Infrastructure as a Service) computer is relatively expensive and any new deployment should include a plan to scale the VM’s resources up/down to prevent unnecessary high machine resources configurations, which will translate into high monthly bills.

Instead of manually switching VMs on or off, or resizing its specs, at set times during the day, this PowerShell script (intended to run periodically in Azure Automation) scales VMs automatically according a pattern set using Azure Tags.

###################

This script looks for and parses the following Azure Tags:

'ScheduledStateHours' - Pattern describing the scheduled hours, business timezone and workdays
    Format:	  [time from-24h]-[time to-24h]|[TimeZone ID]|[workdays; comma separated]
    Example:  '08:00-18:00|W. Europe Standard Time|mon,tue,wed,thu,fri'
              '07:00-23:00|India Standard Time|mon,tue,wed,thu,fri,sat'

'ScheduledStatePattern' - pattern describing desired VM state during and outside scheduled hours, state can be either on or off, or a valid VM size
    Format:	  __[state during scheduled hours]__ | __[state outside scheduled hours]__
    Example:  `on|off`
              `standard_B4ms|standard_B2s`
              `standard_D3_v2_Promo|off`

'ScheduledStateProcess' - boolean value indicating whether the resource should be processed by the script. When omitted, or true, the script will process this VM. When set to false it will be skipped.
    Format:	  [boolean] (true or false)
    Example:  `false`

#>

$ConnectionName = "AzureRunAsConnection"
$ChildRunbookName = "Set-AzureRmVMState"
$AutomationAccountName = "** AUTOMATION ACCT NAME **"
$AutomationRGName = "** AUTOMATION RG NAME **"

#$ErrorActionPreference = "SilentlyContinue"

Write-Verbose 'Get the connection "AzureRunAsConnection"'
$servicePrincipalConnection = Get-AutomationConnection -Name $ConnectionName

"Logging in to Azure..."
Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

function IsMatchingVMState {
    # compare the desired state with actual state
    # return $true of $false depending the outcome of the test
    param ($VM, [string]$RequiredState)

    if (@("on", "off") -contains $RequiredState.ToLower()) {
        # get VM state, check VM running
        $status = (($VM | Get-AzureRmVM -Status ).Statuses | Where { $_.Code -like "PowerState*" }).DisplayStatus

        if (($status -eq "VM Running") -and ($RequiredState -eq "on")) { return $true; }

    }
    else {
        # size change, check current VM size
        $size = ($VM | Get-AzureRmVM ).HardwareProfile[0].VmSize
        if ($size.ToLower() -eq $RequiredState.ToLower() ) { return $true }
    }

    return $false
}


Write-Output "Listing accessible subscriptions..."
$subscriptions = Get-AzureRMSubscription 
$subscriptions | Select Name, SubscriptionId, State | Format-Table -AutoSize

$subscriptions | Foreach-Object { 
    
    Write-Output "`nSwitching to subscription $($_.Name)"
    $subscription = ($_ | Set-AzureRmContext)
   
    # get list of VMs with tag applied tag:BusinessHours, tag:BusinessHoursStatePattern
    Write-Output "Searching for all resources with Tag 'ScheduledStateHours'"
    $resources = Get-AzureRmResource -TagName "ScheduledStateHours"  -ResourceType Microsoft.Compute/virtualMachines

    foreach ($vm in $resources) {


        # store VM information for passing on to action-runbook/function
        $TargetVM = @{ "Name" = $vm.Name; "ResourceGroupName" = $vm.ResourceGroupName; "SubscriptionId" = $subscription.Subscription }

        # read tags
        Write-Output "`n____________________________________________`n" `
            "Processing rules for $($vm.Name)"

        # TODO: Check for BusinessHoursProcess should go here
        # Currently at end of the script to show all (calculated) times and values for troubleshooting

        $businesshours = $vm.Tags["ScheduledStateHours"]
        $pattern = $vm.Tags["ScheduledStatePattern"]

        # grab configuration from the tags
        $timezone = ($businesshours.Split("|")[1]) # extract the timezone

        # calculate time in timezone
        $utc = [System.DateTime]::UtcNow
        $tz = [TimeZoneInfo]::FindSystemTimeZoneById($timezone) # "W. Europe Standard Time"
        if ($tz -eq $null) {
            Write-Error "TimeZone $($timezone) not found. Skipping."
            continue
        }
        $offset = $tz.GetUtcOffset($utc).TotalHours

        $tzTime = [TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz)
        $tzDate = $tzTime.Date

        # calculating scheduled hours
        $days = $businesshours.Split("|")[2].Split(",") # extracting the working days from the bussiness hours tag
        $times = $businesshours.Split("|")[0].Split("{-}") # extracting scheduled hours
        $start = $tzDate.AddHours([int]$times[0].Split(":")[0]).AddMinutes([int]$times[0].Split(":")[1]) # scheduled hours start
        $stop = $tzDate.AddHours([int]$times[1].Split(":")[0]).AddMinutes([int]$times[1].Split(":")[1]) # scheduled hours stop

        Write-Output "`tScheduled hours:  $($times[0])-$($times[1])" `
            "`tTimezone:        $timezone" `
            "`tTZ Offset:       $($tz.DisplayName)"

        # determine of today is a workday
        $now = $tzTime # calculate current time (including offset)
        $isworkday = (($now.DayOfWeek).ToString().ToLower().Substring(0, 3) -in $days) # check if today is workday

        $desiredState = $null
        $businessHours = "no"
        $params = $null

        # determine WHATaction is required and kick off Set-AzureRmVMState if needed
        if ($isworkday -and ($now -gt $start -and $now -lt $stop)) {
            $businessHours = "yes"
            $desiredState = $($pattern.Split("|")[0])
            $params = @{ "VM" = $TargetVM; "DesiredState" = $desiredState }
            #Update-AzureRmVMScheduledState -VM $TargetVM -DesiredState $($pattern.Split("|")[0])
        }
        elseif ($isworkday -eq $false -or ($now -lt $start -or $now -gt $stop)) {
            $businessHours = "no"
            $desiredState = $($pattern.Split("|")[1])
            $params = @{ "VM" = $TargetVM; "DesiredState" = $desiredState }
        }

        # check whether Tag that control if this VM can be controled by this script is set
        # if set, check if set to false, which would mean 'GO AWAY!'
        if ($vm.Tags["ScheduledStateProcess"] -ne $null) {
            $processbusinesshours = $vm.Tags["ScheduledStateProcess"].ToLower()
            If ($processbusinesshours -eq "false") {
                Write-Output "`t*** Tag ScheduledStateProcess set to 'false', skipping"
                continue
            }
        }
        ElseIf ($params -ne $null) {

            $matchesState = (IsMatchingVMState -VM $vm -RequiredState $desiredState)
            Write-Output "`n`tIt's now $($now)" `
                "`tScheduled hours:  $($businessHours)" `
                "`tDesired state:   $($desiredState)"
            "`tMatches current: $($matchesState)"

            if ($matchesState -eq $true) {
                Write-Output "`tAlready in desired state, skipping"
            }
            else {
                Write-Output "`t*** Changing state, starting runbook"
                Start-AzureRmAutomationRunbook `
                    –Name $ChildRunbookName –Parameters $params `
                    –AutomationAccountName $AutomationAccountName `
                    -ResourceGroupName $AutomationRGName
            }

        }
        Else { Write-Output "`tUnknown state, skipping..."  }

    }

}