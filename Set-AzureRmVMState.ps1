<#
Sets Azure Rm VM to a desired state
Version: 0.2
Author: Dirk Dulfer
Date: 31 July 2018

Change state of size of an Azure RM Virtual Machine based on parameters passed into this script
  Param ([object]$VM, $DesiredState)

# parameters
  [object]$VM - Expected content and structure:
    @{ "Name" = $vm.Name; "ResourceGroupName" = $vm.ResourceGroupName }

  [string]$DesiredState -
    'on', 'off' or a valid VM size (supported by this particular VM)

# TODO:
- [ ] clean shutdown prior to updating size
  [ ] add support for controling VMs in other subscriptions

#>

[CmdletBinding()]
[OutputType([string])]
Param ([object]$VM, $DesiredState)

$ConnectionName = "AzureRunAsConnection"

Write-Verbose 'Get the connection "AzureRunAsConnection"'
$servicePrincipalConnection = Get-AutomationConnection -Name $ConnectionName

Write-Output "Logging in to Azure..."
Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null


Write-Output "`tProcessing $($VM.Name)..."

if (("on", "off") -contains $DesiredState.ToLower()) {
    $v = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name -Status
    if (($v.Statuses.DisplayStatus -contains "VM running") -and ($DesiredState.ToLower() -eq "off")) {

        # TODO: clean shutdown prior to updating size

        Write-Output "`tSwitching $DesiredState now..."
        $v | Stop-AzureRmVM -Force
    }
    elseif ($v.Statuses.DisplayStatus -contains "VM deallocated" -and $DesiredState.ToLower() -eq "on") {
        Write-Output "`tSwitching $DesiredState now..."
        $v | Start-AzureRmVM
    }
    elseif ($v.Statuses.DisplayStatus -contains "VM running" -and $DesiredState.ToLower() -eq "on") {
        Write-Output "`tVM already on..."
    }
    elseif ($v.Statuses.DisplayStatus -contains "VM deallocated" -and $DesiredState.ToLower() -eq "off") {
        Write-Output "`tVM already deallocated..."
    }
    else {
        Write-Output "Unknown state, skipping..."
    }
}
else {
    $v = Get-AzureRmVM -ResourceGroupName $VM.ResourceGroupName -Name $VM.Name
    if ($v.HardwareProfile.VMSize.ToString().ToLower() -ne $DesiredState.ToLower()) {
        Write-Output "`tScaling machine from $($v.HardwareProfile.VMSize.ToLower()) to $DesiredState"

        # TODO: clean shutdown prior to updating size

        # resize the VM
        $v.HardwareProfile.VmSize = $DesiredState
        $v | Update-AzureRmVm


        $v = $v | Get-AzureRmVM -ResourceGroupName -Status
        if ($v.Statuses.DisplayStatus -contains "VM deallocated") {
            Write-Output "`tSwitching on now..."
            $v | Start-AzureRmVM
        }

    }
    else {
        Write-Output "`tMachine in desired state ($DesiredState), skipping..."
    }

}