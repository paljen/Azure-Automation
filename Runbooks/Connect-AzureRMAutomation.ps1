
<#
.DESCRIPTION
    Logs into azure resource manager and returns the automation account information to the calling runbook

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
    Version  : 1.0
    Template : Component
    tVersion : 2.2
    Author   : Palle Jensen (PJE)
    Note     : {[Major.Minor]} - {Date}, {Username}, {Description}
    Note     : 1.0 - 21-02-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Connect-AzureRMAutomation"

try
{
    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "`$RunbookName variable not initialized"}

    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")

    $ResourceGroupName = Get-AutomationVariable -Name "AzAutomationResourceGroupName" 
    $AutomationAccountName = Get-AutomationVariable -Name "AzAutomationAccountName"
    $SubscriptionId = Get-AutomationVariable -Name "AzAutomationSubscriptionId"
    $Credentials = Get-AutomationPSCredential -Name "AzService-Automation"

    # Login to authenticate cmdlets with Azure Resource Manager
    Login-AzureRmAccount -Credential $Credentials -OutVariable Login
    $rbLog.WriteLogEntry($RunbookName, "Successfully Logged into Azure Resource Manager")

    # Select Subscription to work on
    Select-AzureRmSubscription -SubscriptionId $SubscriptionId -OutVariable Subscription
    $rbLog.WriteLogEntry($RunbookName, "Selected Subscription $($Subscription.subscription.SubscriptionName)")
                                    
    # Get Automation account informations
    Get-AzureRmAutomationAccount -Name $AutomationAccountName -ResourceGroupName $ResourceGroupName -OutVariable AutomationAccount
    $rbLog.WriteLogEntry($RunbookName, "Automation Account $($AutomationAccount.AutomationAccountName)")
       
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'AutomationAccount' = $AutomationAccount
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'AutomationAccount' = $null
                        'ObjectCount' = 0
    }

    Write-Error $excep -ErrorAction Continue
}
finally
{
    $rbLog.WriteLogEntry($RunbookName,"Runbook finished - total runtime: $((([DateTime]::Now) - $StartTime).TotalSeconds) Seconds")
    $rbLog.Log.GetEnumerator() | foreach { Write-Verbose "$($_.RunbookName), $($_.Message), $($_.TimeStamp)" }

    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}
