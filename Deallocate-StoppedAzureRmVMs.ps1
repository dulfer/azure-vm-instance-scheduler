# Stops Azure RM VMs that are stopped, but not deallocated
# VMs can be excluded from being touched by this script by 
# setting a Tag 'AutoDeallocate' with value 'false'

$ConnectionName = "AzureRunAsConnection"
$AutoDeallocateTagName = "AutoDeallocate"

Write-Verbose 'Get the connection "AzureRunAsConnection"'
$servicePrincipalConnection = Get-AutomationConnection -Name $ConnectionName         

Write-Verbose "Logging in to Azure..."
Add-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 

Write-Output "Listing available subscriptions..."
Get-AzureRMSubscription | Foreach-Object { 
    
    Write-Output "Switching to subscription $($_.SubscriptionName)"
    $_ | Set-AzureRmContext | Out-Null
    
    Write-Verbose "Searching for all resources with PowerState 'VM Stopped'" # Tag 'AutoDeallocate' and value 'True'"
    $vms = Get-AzureRmVM -Status | Where-Object { $_.PowerState -eq "VM Stopped" }

    if ($vms -eq $null) { Write-Output "No stopped but allocated VMs found." }

    foreach ($vm in $vms) {
        $psvm = ($vm | Get-AzureRmVM)
        if (($psvm.Tags[$AutoDeallocateTagName] -eq $null) -or ([bool]$psvm.Tags[$AutoDeallocateTagName] -ne $false)) {
            Write-Output "Stopping VM $($vm.Name) as its current state is '$($vm.PowerState)'"
            $vm | Stop-AzureRmVM -Force
        } else {
            Write-Output "VM $($vm.Name) marked excluded from Auto-Deallocation"
        }
    }

}