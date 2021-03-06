
<#
.DESCRIPTION
    A brief description on what is going on in the runbook

    Runbook Tagging
    •	Modular, reusable – single purpose runbooks. - Tag: Component
    •	Modular, reusable – single purpose runbooks used in Components - Tag: Core
    •	Non modular, made for a specific purpose - Tag: Script   
    •	Flow specific runbooks - Tag: Controller
    •	Integration runbooks combined with webhooks - Tag: Interface

.PARAMETER  <ParameterName>
	The description of a parameter. (Add .PARAMETER keyword for each parameter)

.OUTPUTS
    [Object]

.NOTES
    rVersion : 1.0
    Template : Control
    tVersion : 2.1
    Author   : {Username}		
    Note     : {[Major.Minor]} - {Date}, {Username}, {Description}
    Note     : 1.0 - 21-02-2017, Admin-PJE, Initial template development
    Note     : 2.0 - 28-09-2017, Admin-PJE, Logging implemented
    Note     : 2.1 - 21-09-2017, Admin-PJE, Added verbose output and some minor logging details
#>

[CmdletBinding()]

Param(
    
    <# Adjust Parmameters to what is needed
    [Parameter(Mandatory=$true)]
    [String]$Name#>

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
    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "Please initialize the `$RunbookName variable"}

    $StartTime = Get-date

    # Initialize workspace and repositories
    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1

    # Initialize Logging
    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    # If the log file is larger then 2 MB rename the the file, a new log file will be gererated
    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")

    # Optional - Connect to Azure Resource Manager, ignore if this is called from an Control runbook 
    # Where connection already has been initialized with the variable `$conn
    try{
        Get-AzureRmAutomationAccount | Out-Null
    }
    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        
        # Write Log entries from sub runbook
        $rbLog.WriteLogEntry($conn)

        if($conn.status -ne "Success"){
            Throw "Error - Connecting to Azure failed"
        } 
    }

    # General flow is Execute component runbook, extract the Log and check the status of the runbook

    # Execute runbook to create on-premises AD user
    $usr = .\New-OnPremADUser.ps1 @usrParams

    $rbLog.WriteLogEntry($usr)
    
    # Throw exception if something went wrong
    if($usr.Status -eq "Failed"){
          Throw $usr.Message
    }

    # Execute runbook to create on-premises AD user
    $mb = .\Enable-OnPremiseUserMailbox.ps1 @mbParams

    $rbLog.WriteLogEntry($mb)
    
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
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'ObjectCount' = 0
    }

    Write-Error $excep -ErrorAction Continue
}
finally
{
    # Build and send report via mail    
    $r = [RunbookReport]::new()
    $r.setStyle([Style]::DarkBlue)
    $r.addContent("Trace Log",$($rbLog.Log).psobject.BaseObject)
    $report = $r.getReport()
   
    # optional, use Send-Email to send email or sms notifications, for sms use EmailAddressTo file with +45xxxxxxxx@sms.ecco.local
    $email = .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Daily Report $RunbookName" -Body $report -AsHtml
    $rbLog.WriteLogEntry($email)

    $rbLog.WriteLogEntry($RunbookName,"Runbook finished - total runtime: $((([DateTime]::Now) - $StartTime).TotalSeconds) Seconds")
    $rbLog.Log.GetEnumerator() | foreach { Write-Verbose "$($_.RunbookName), $($_.Message), $($_.TimeStamp)" }
   
    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}
