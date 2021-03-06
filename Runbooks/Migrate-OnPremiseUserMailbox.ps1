
<#
.DESCRIPTION
    Workflow for migrating mailbox to Office365 (hybrid).

    The script starts connecting to Azure, MSOnline and Exchange On-Premise.

    A list of mailbox objects are then populated that has an E1 License in MSOnline.

    If the list is not empty, a runbook, to make the move requests (migrations), 
    are then called with the polulated list of mailbox objects.

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
    Note     : 1.0 - 21-01-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(
    
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Migrate-OnPremiseUserMailbox"

try
{
    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "`$RunbookName variable not initialized"}

    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1
    . $ws\AzureAutomation\Repository\Classes\Report.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")

    try{
        Get-AzureRmAutomationAccount | Out-Null
    }
    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        
        $rbLog.WriteLogEntry($conn)

        if($conn.status -ne "Success"){
            Throw "Error - Connecting to Azure failed"
        } 
    }
           
    $modules = @()
    $modules += .\Connect-MSOnline.ps1
    $modules += .\Connect-ExchangeOnPrem.ps1

    $rbLog.WriteLogEntry($modules)

    # Make sure that the modules were imported
    if($modules[0].ObjectCount -lt 1 -or $modules[1].ObjectCount -lt 1){
        Throw "One or more modules failed importing"
    }

    # Get all onprem mailboxes in ECCO OU that have an Office 365 license 
    $ou = "OU=ECCO,DC=prd,DC=eccocorp,DC=net"
    $exclude = "\b(TERMINATED USERS)\b"     
    
    $mb = Get-Mailbox -ResultSize Unlimited -Filter {UserPrincipalName -like "*@ecco.com"} -OrganizationalUnit $ou |  foreach {
            try{
                Get-ADUser -identity $_.Guid | Where-Object {$_.enabled -eq $true -and $_.DistinguishedName -notmatch $exclude} | Foreach {
                    try{
                        Get-MsolUser -UserPrincipalName $_.UserPrincipalName | ? {$_.Islicensed -eq $true} | foreach {
                            try{
                                Get-Mailbox $_.UserPrincipalName
                                $rbLog.WriteLogEntry($RunbookName, "$($_.UserPrincipalName): Is Licensed and has an On-Premis Mailbox")
                            }
                            catch{
                                $rbLog.WriteLogEntry($RunbookName, "$($_.UserPrincipalName): Has no on-premis mailbox, $($_.exception.message)")
                            }
                        }
                    }
                    catch{
                            $rbLog.WriteLogEntry($RunbookName, "User not in Azure AD, $($_.exception.message)")
                    }
                }
            }
            catch{
                $rbLog.WriteLogEntry($RunbookName, "$($_.UserPrincipalName): $($_.exception.message)")
            }
    }

    if($mb -ne $null)
    {
        $par = @{'UserPrincipalName'=$mb.UserPrincipalName}
        $job = Start-AzureRmAutomationRunbook -Name "New-O365MailboxMigration" -Parameters $par -ResourceGroupName $($conn.AutomationAccount.ResourceGroupName) -AutomationAccountName $($conn.AutomationAccount.AutomationAccountName) -RunOn "ECCO-DKHQ" -Wait
        
        $rbLog.WriteLogEntry($job)
    }
    else
    {
        $rbLog.WriteLogEntry($RunbookName, "No Mailboxes to migrate")
    }

    if($($job.MoveRequest) -eq $null){
        $mReqData = [Ordered]@{'MailboxIdentity'= $null;'ExchangeGuid'=$null;'ArchiveGuid'=$null;'TotalMailboxSize'=$null;'TotalMailboxItemCount'=$null;'TotalArchiveSize'=$null;'TotalArchiveItemCount'=$null}
        $mRequest = New-Object -TypeName PSObject -Property $mReqData
    }
    else{
        $mRequest = $job.MoveRequest
    }
    
    # Return values used for further processing, add properties if needed
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
    Remove-PSSession -name $($modules[1].Connect.Session.Name) -ErrorAction SilentlyContinue

    $rbLog.WriteLogEntry($RunbookName,"Runbook finished - total runtime: $((([DateTime]::Now) - $StartTime).TotalSeconds) Seconds")
    $rbLog.Log.GetEnumerator() | foreach { Write-Verbose "$($_.RunbookName), $($_.Message), $($_.TimeStamp)" }

    $r = [RunbookReport]::new()
    $r.setStyle([Style]::DarkBlue)
    $r.addContent("$($env:COMPUTERNAME) Daily Report for $runbookname runbook",$mRequest)
    $r.addContent("Trace Log",$rbLog.Log.psobject.BaseObject)
    $report = $r.getReport()

    # for sms use EmailAddressTo file with +45xxxxxxxx@sms.ecco.local
    $email = .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Daily Report $RunbookName" -Body $report -AsHtml
    $rbLog.WriteLogEntry($email)


    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}

