<#
.SYNOPSIS
    Recovers the VM by performing a disk swap of the OS disk to the fixed os disk

.DESCRIPTION
    Occasionally Azure IaaS VMs (Microsoft.Compute/virtualMachines) may not start because there is something wrong with the operating system (OS) disk preventing it from booting up correctly.
    In such cases it is a common practice to recover the problem VM by first creating a resue VM, attaching the OS Disk of the problem VM to the rescue VM and then fixing the os Disk. Once the OsDisk is fixed 
    the script is then executed to perform the following steps 
	-Detach the OS disk that was attached as a data disk to the rescue VM
	-Disk Swap  OS Disk of the Problem VM with the fixed OS Disk Uri
    -Start the VM
    -Delete all the resources that were created for the rescue VM

.PARAMETER VmName
    This is a mandatory Parameter, Name of the VM that needs to be recovered.

.PARAMETER ResourceGroup
    This is a mandatory Parameter, Name of the ResourceGroup the VM belongs to.

.PARAMETER SubID
    This is a mandatory Parameter, SubscriptionID - the VM belongs to.

.PARAMETER FixedOsDiskUri
    This is a mandatory Parameter, This would be the uri of the fixedOSDisk, this information will be provided after the successful execution of CreateCRPRescueVM.

.PARAMETER prefix
    Optional Parameter. By default the new Rescue VM and its resources are all created under a ResourceGroup named same as the orginal resourceGroup name with a prefix of 'rescue', however the prefix can be changed to a different value to overide the default 'rescue'



.EXAMPLE
    .\RecoverCRPVM.ps1 -ResourceGroup "rescueportalLin" -VmName "ubuntu2" -SubID "xxxxxxxx-abdf-4aaf-8868-2002dfeea60c" -FixedOsDiskUri "https://vmrecoverytestdisks645.blob.core.windows.net/vhds/fixedosfixedosubuntu220171220164151.vhd" -prefix "rescuered"

.NOTES
    Name: CreateCRPRescueVM.ps1

    Author: Sujasd
#>

Param(
        [Parameter(mandatory=$true)]
        [String]$VmName,

        [Parameter(mandatory=$true)]
        [String]$ResourceGroup,

        [Parameter(mandatory=$true)]
        [String]$SubID,

        [Parameter(mandatory=$true)]
        [String]$FixedOsDiskUri,

        [Parameter(mandatory=$false)]
        [String]$prefix = "rescue"
     )


$Error.Clear()
cls
if (-not $showErrors) {
    $ErrorActionPreference = 'SilentlyContinue'
}

$script:scriptStartTime = (Get-Date).ToUniversalTime()
$LogFile = $env:TEMP + "\DiskSwap" + $VmName + "_" + ( Get-Date $script:scriptStartTime -f yyyyMMddHHmmss ) + ".log"  
# Get running path
$RunPath = split-path -parent $MyInvocation.MyCommand.Source
cd $RunPath
$CommonFunctions = $runPath+"\Common-Functions.psm1"

$CommonFunctions = $runPath+"\Common-Functions.psm1"

if (Get-Module Common-Functions) {remove-module -name Common-Functions}   
Import-Module -Name $CommonFunctions  -ArgumentList $LogFile -ErrorAction Stop 

if (-not (Get-AzureRmContext).Account)
{
    Login-AzureRmAccount
}
write-log "Info: Log is being written to ==> $LogFile" 
#Set the context to the correct subid
Write-Log "Setting the context to SubID $SubID" -color Yellow
$subContext= Set-AzureRmContext -Subscription $SubID
if ($subContext -eq $null) 
{
    Write-Log "Unable to set the Context for the given subId ==> $SubID, Please make sure you first  run the command ==> Login-AzureRMAccount" -Color Red
    return
}

#Step 1 Get the VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$ResourceGroup`" -Name `"$VmName`"" -Color Yellow
$vm = Get-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VmName 
if (-not $vm)
{
    Write-Log "Unable to find the VM `"$VmName`",  cannot proceed, please verify the VM name and the resource group name." -Color Red
    return
}
Write-Log "Successfully got the VM Object info for ==> $($vm.Name)" -Color Green

if ($vm.StorageProfile.OsDisk.OsType -eq "Windows") {$windowsVM= $true} else {$windowsVM= $false}

$Vmname = $vm.Name
$rescueVMNname = "$prefix$Vmname"
$RescueResourceGroup = "$prefix$ResourceGroup"

#Step 2 Get the Rescue VM Object
Write-Log "Running Get-AzureRmVM -ResourceGroupName `"$RescueResourceGroup `" -Name `"$rescueVMNname`"" -Color Yellow
$rescuevm = Get-AzureRmVM -ResourceGroupName $RescueResourceGroup -Name $rescueVMNname
if (-not $rescuevm)
{
    Write-Log "Unable to find the VM `"$rescueVMNname`",  cannot proceed, please verify the VM name and the resource group name." -Color Red
    return
}
Write-Log "Successfully got the VM Object info for the Rescue VM ==>  $rescueVMNname" -Color Green

#Step 3 -Removing the DataDisk from Rescue VM
$FixedOsDiskUri  = $FixedOsDiskUri.Replace("`r`n","")
$VHDNameShort = ($FixedOsDiskUri.Split('/')[-1]).split('.')[0]
write-log "VHDNameShort ==> $($VHDNameShort)" -logonly
Write-Log "Removing the Data disk from the Rescue VM ==>  $rescueVMNname" -Color Yellow
Remove-AzureRmVMDataDisk -VM $rescuevm -Name $VHDNameShort
Update-AzureRmVM -ResourceGroupName $RescueResourceGroup -VM $rescuevm
Write-Log "Successfully removed the Data disk from the Rescue VM ==>  $rescueVMNname" -Color Green

#Stop the VM before performing the disk swap.
Write-Log "Stopping the VM ==> $VmName"  -Color Yellow

$stopped = StopTargetVM -ResourceGroup $ResourceGroup -VmName $VmName
write-log "`"$stopped`" ==> $($stopped)" -logOnly
if (-not $stopped) 
{
   write-log   "$($Stopped)" -logonly
   Write-Log "Unable to stop the  VM ==> $VmName successfully, try manully stopping the VM from portal" -Color Red
   Return
}


#Step 4 -Disk Swapping the OS Disk to point to the fixed OSDisk Uri

Write-Log "Disk Swapping the OS Disk, to point to the fixed OS Disk for VM ==>  $VmName" -Color Yellow
#before setting the uri, ensure to remove any new line characters
#$FixedOsDiskUri  = $FixedOsDiskUri.Replace("`r`n","")
$vm.StorageProfile.OsDisk.Vhd.Uri = $FixedOsDiskUri 
Update-AzureRmVM -ResourceGroupName $ResourceGroup -VM $vm 
Write-Log "Successfully Disk Swapped the OS Disk,  for VM ==>  $VmName" -Color Yellow

#Step 5 -Start the VM
Write-Log "Starting the VM ==> $VmName"  -Color Yellow
$started= Start-AzureRmVM -ResourceGroupName $ResourceGroup -Name $VmName
if ($Started)
{
   Write-Log "Successfully started the  VM ==> $VmName" -Color Green
}
else
{
   Write-Log "Unable to  start the  VM ==> $VmName, Please try it manually and RDP into it" -Color red
   return
}

#Step 5 Open a RDP Connection to the VM
if ($windowsVM)
{
    Write-log "Opening the RDP file to connect to the  VM ==> $VmName" 
    Get-AzureRmRemoteDesktopFile -ResourceGroupName $ResourceGroup -Name $VmName -Launch
}

Write-Host "`nWere you able to successfully recover the VM ==> $VmName and are you ready to delete all the rescue reources that were created under the Resource Group $RescueResourceGroup (Y/N)?" -ForegroundColor Yellow
if ((read-host) -eq 'Y' -or (read-host) -eq 'y')
{
    Write-Log "Acknowledged deleting the rescource group ==> $RescueResourceGroup" -color Cyan
    Remove-AzureRmResourceGroup -Name $RescueResourceGroup -Force
}
else
{
    Write-Log "Did not acknowledge deleting the rescource group ==> $RescueResourceGroup" -color Cyan
}









