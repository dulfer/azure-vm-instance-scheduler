# azure-vm-instance-scheduler

Set Azure VM power state or scale its size according a time schedule pattern, declared with Azure Tags

Microsoft Azure offers a fast, flexible and easily scalable platform for hosting Virtual Machine workloads. However, this so called IaaS (Infrastructure as a Service) computer is relatively expensive and any new deployment should include a plan to scale the VM’s resources up/down to prevent unnecessary high machine resources configurations, which will translate into high monthly bills.

Instead of manually switching VMs on or off, or resizing its specs, at set times during the day, this PowerShell script (intended to run periodically in Azure Automation) scales VMs automatically according a pattern set using Azure Tags.

![](https://github.com/dulfer/azure-vm-businesshours-state/raw/master/.github/AzureVM-Tags-BusinessHours-Microsoft%20Azure.jpg?s=600)

__Note thate there *will be* downtime when rescaling VMs__  
*Azure Tags are only available for Azure RM resources (ARM). Azure Tags cannot be assigned to VMs that are deployed using Classic compute and therefore cannot be controlled using this script.*  

## Quick Reference
### *Tag:* ScheduledStateHours
*Pattern describing the scheduled hours, timezone and workdays*  
Format:	  __[time from]__ - __[time to]__ | __[TimeZone ID]__ | __[workdays; comma separated]__  
Example:  
    `08:00-18:00|W. Europe Standard Time|mon,tue,wed,thu,fri`  
    `07:00-20:00|Central America Standard Time|mon,tue,wed,thu,fri,sat`  

*An overview of available TimeZoneIDs can be found here:* [TimeZoneIDs.md](https://github.com/dulfer/azure-vm-businesshours-state/blob/master/TimeZoneIDs.md)

### *Tag:* ScheduledStatePattern ###
*Definition of the VM state or size during and outside scheduled hours.*  
State can either be on or off, or a VM size to scale to.  
Format:	  __[state during scheduled hours]__ | __[state outside scheduled hours]__  
Example:  
  `on|off`  
  `standard_B4ms|standard_B2s`  
  `Standard_D3_v2_Promo|off`  

*An overview of available VM sizes in your Azure region can be requested using this PowerShell script.*  
```PowerShell 
Get-AzureRmVMSize -Location "West Europe"  
# change the location to whatever Azure region  you would like an overview for
```

### *Tag:* ScheduledStateProcess
*Indicates whether the resource should be processed by the script.  
When omitted, or true, the script will process this VM. When set to false it will be skipped.*  
Format:	  [boolean] (true or false)  
Example:  `false`  


## TODO
- [X] Code the script and commit  
- [ ] Complete readme, add some images on how to setup in Azure  
- [X] Add reference to overview of timezone IDs  
- [ ] ?? Include overview of available VM sizes *quickly outdated* ??  
