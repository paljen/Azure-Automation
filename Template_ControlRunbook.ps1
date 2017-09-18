
<#
.DESCRIPTION
    A brief description on what is going on in the runbook

    Control runbooks 
    •	Flow control for particular use case where more components or scripts are a part of.
    •	Can be initiated from all higher tier runbooks (Interfaces, Init)
    •	Connects to azure resource manger if needed

.INPUTS
    NA

.OUTPUTS
    [Object]

.NOTES
    Version:        1.0.0
    Author:			
    Creation Date:	
    Purpose/Change:	Initial runbook development
#>

Param(

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal. Use Write-Verbose 
   in the runbook to write to verbose stream#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = ""

try
{
    # Load classes
    $repo = Get-AutomationVariable -Name Repository
    . $repo\Classes\Log.ps1
    . $repo\Classes\Report.ps1
    
    # Initialize runbook Log
    [Array]$instance = [RunbookLog]::New()

    # Clone Logging Array to ArrayList to utalize array methods
    [System.Collections.ArrayList]$Log = $instance.Clone()

    # Clear Cloned array for default entry
    $Log.clear()

    # Initialize trace output stream, if the runbook is run in Azure the computername will return CLIENT
    $Log.Add($Instance.WriteLogEntry($RunbookName,"Running on ($env:COMPUTERNAME)")) | Out-Null

    # Optional - Connect to Azure Resource Manager, ignore if this is called from an Control runbook 
    # Where connection already has be initialized with the variable `$conn
    try{        
        Get-AzureRmAutomationAccount | out-null
    }

    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        
        foreach ($i in $conn.Trace){
            $Log.Add($instance.WriteLogEntry($i.RunbookName,$i.Message)) | Out-Null
        }

        if($conn.status -ne "Success"){
            Throw "Error - Connecting to Azure failed"
        }
    }

    # General flow is Execute component runbook, extract the Log and check the status of the runbook

    # Execute runbook to create on-premises AD user
    $usr = .\New-OnPremADUser.ps1 @usrParams

    # Recieve log from sub runbook
    foreach ($i in $usr.Trace){
        $Log.Add($Instance.WriteLogEntry($i.RunbookName,$i.Message)) | Out-Null
    }
    
    # Throw exception if something went wrong
    if($usr.Status -eq "Failed"){
          Throw $usr.Message
    }

    # Execute runbook to create on-premises AD user
    $mb = .\Enable-OnPremiseUserMailbox.ps1 @mbParams

    # Recieve log from sub runbook
    foreach ($i in $mb.Trace){
        $Log.Add($Instance.WriteLogEntry($i.RunbookName,$i.Message)) | Out-Null
    }
    
    # Throw exception if something went wrong
    if($mb.Status -eq "Failed"){
          Throw $mb.Message
    }
                 
    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Workflow Finished Successfully"
                        'ObjectCount' = 1
    }
}
catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
    $Log.Add($instance.WriteLogEntry($RunbookName,"Exception Caught at line $($_.InvocationInfo.ScriptLineNumber), $excep")) | Out-Null

    # Return values to component runbook
    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'Account' = $null
                        'ObjectCount' = 0
    }

    Write-Error $excep -ErrorAction Continue
}
finally
{
    # Build and send report via mail    
    $r = [RunbookReport]::new()
    $r.setStyle([Style]::DarkBlue)
    $r.addContent("Trace Log",$Log.psobject.BaseObject)
    $report = $r.getReport()

   
    # optional, use Send-Email to send email or sms notifications, for sms use EmailAddressTo file with +45xxxxxxxx@sms.ecco.local
    $email = .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Daily Report $RunbookName" -Body $report -AsHtml

    # Recieve log from sub runbook $modules.trace
    foreach ($i in $email.trace){
        $Log.Add($instance.WriteLogEntry($i.RunbookName,$i.Message)) | Out-Null
    }

    $props.Add('Trace',$Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}