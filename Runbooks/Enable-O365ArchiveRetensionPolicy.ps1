
<#
.DESCRIPTION
    Enable retention policy on mailbox in O365 both migrated and non migrated mailbox.

    regardless of archive is enabled. The script starts connecting to Azure, MSOnline and Exchange Online.

    A list of mailbox objects are then populated with a filter where the Name is not DiscoverySearchMailbox 
    and the retention policy is not like Ecco*. 
    
    Retention policy is then set for objects in that list.

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
$RunbookName = "Enable-O365ArchiveRetensionPolicy"

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
           
    $modules = @()
    $modules += .\Connect-ExchangeOnline.ps1

    $rbLog.WriteLogEntry($modules)

    if($modules[0].ObjectCount -lt 1)
    {
        Throw "failed - One or more modules was not imported"
    }

    # Get O365 mailboxes with an archive and set retentionpolicy
    $rPolicy = "ECCO Default Retention Policy"
    $rbLog.WriteLogEntry($RunbookName, "Retention Policy: $rPolicy")

    $mb = Get-Mailbox -ResultSize Unlimited -Filter {Name -NotLike "DiscoverySearchMailbox*"} | ? {$_.RetentionPolicy -notlike  "Ecco*"}

    if ($mb.count -gt 0)
    {
        $mb | Foreach {
            try{
                Set-Mailbox -Identity $_.UserPrincipalName -RetentionPolicy $rPolicy
                $rbLog.WriteLogEntry($RunbookName, "Successfully set Retention Policy for user: $($_.UserPrincipalName)")
            }
            catch
            {
                $rbLog.WriteLogEntry($RunbookName, "$($_.exception.message)")
            }
        }
    }
    else
    {
        $rbLog.WriteLogEntry($RunbookName, "Get-Mailbox returned no mailboxes")
    }
       
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'ObjectCount' = 0
    }

    Write-Error $excep -ErrorAction Continue
}
finally
{
    Remove-PSSession -name $($modules[0].Connect.Session.Name) -ErrorAction SilentlyContinue

    $rbLog.WriteLogEntry($RunbookName,"Runbook finished - total runtime: $((([DateTime]::Now) - $StartTime).TotalSeconds) Seconds")
    $rbLog.Log.GetEnumerator() | foreach { Write-Verbose "$($_.RunbookName), $($_.Message), $($_.TimeStamp)" }

    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Runbook - $RunbookName Status" -Body $out

    Write-Output $out
}
