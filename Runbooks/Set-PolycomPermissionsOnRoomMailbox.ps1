
<#
.DESCRIPTION

    Setting full access permissions for the user Service-PolycomEndpo on all Room Mailboxes

    The script starts connecting to Azure and Exchange OnPremise.
    
    A list of Room Mailbox objects are populated and Permissions are added for each mailbox

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
    Note     : 1.0 - 13-02-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(
    
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Set-PolycomPermissionsOnRoomMailbox"

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
    $modules += .\Connect-ExchangeOnPrem.ps1

    $rbLog.WriteLogEntry($modules[0])

    # Make sure that the modules were imported for the runspace
    if($modules[0].ObjectCount -lt 1){
        Throw "Error - One or more modules was not imported"
    }
              
    filter RoomMailbox
    {
       $input | Where { $_.OrganizationalUnit -like "prd.eccocorp.net/EXCHANGE/*" -and $_.RecipientTypeDetails -eq "RoomMailbox" } 
        
    }
 
    $params = @{}
    $params.Add('User','Service-PolycomEndpo')
    $params.Add('AccessRights','Fullaccess')
    $params.Add('InheritanceType','all')

    Get-Mailbox -resultsize unlimited | RoomMailbox | foreach {
        $perm = Add-MailboxPermission -Identity $_.UserPrincipalName @params
        $rbLog.WriteLogEntry($RunbookName, "RoomMailbox $($_.UserPrincipalName) State: $($perm.ObjectState)")
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

    Write-Output $out
}
