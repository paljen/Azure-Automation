 
<#
.DESCRIPTION
    Create new user object in Active Directory on-premises

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
    Author   : Palle Jensen		
    Note     : {[Major.Minor]} - {Date}, {Username}, {Description}
    Note     : 1.0 - 21-02-2017, Palle Jensen, Initial runbook development
#>

[CmdletBinding()]

Param(

    [Parameter(Mandatory=$true)]
    [String]$Name,

    [Parameter(Mandatory=$true)]
    [String]$Givenname,

    [Parameter(Mandatory=$true)]
    [String]$Displayname,

    [Parameter(Mandatory=$true)]
    [String]$SamAccountName,

    [Parameter(Mandatory=$true)]
    [String]$UserPrincipalName,

    [Parameter(Mandatory=$true)]
    [String]$OrganizationalUnit,

    [Parameter(Mandatory=$true)]
    [String]$DomainController

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "New-ADUserOnPremise"

try
{
    # Create hashtable with parameters
    $params = @{}
    $params.Add('Name',$Name)
    $params.Add('Givenname',$Givenname)
    $params.Add('Displayname',$Displayname)
    $params.Add('SamAccountName',$SamAccountName)
    $params.Add('UserPrincipalName',$UserPrincipalName)
    $params.Add('Path',$OrganizationalUnit)
    $params.Add('Server',$DomainController)
    $params.Add('PassThru',$true)
    $params.Add('Enabled',$true)
    $params.Add('ChangePasswordAtLogon',$true)

    $pwd = "P@ssw0rd1234!"
    $params.Add('AccountPassword',(ConvertTo-SecureString $pwd -AsPlainText -Force))#>

    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "`$RunbookName variable not initialized"}

    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    # If the log file is larger then 2 MB rename the the file, a new log file will be gererated
    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")
           
    $modules = @()
    $modules += Import-Module ActiveDirectory -PassThru

    # Make sure that the modules were imported for the runspace
    if($modules[0].Count -lt 1)
    {
        Throw "Error - One or more modules was not imported"
    }
            
    $rbLog.WriteLogEntry($RunbookName,"Successfully imported module $($modules[0].Name)")
    $rbLog.WriteLogEntry($RunbookName,"Active domain controller is $($DomainController)")
    
    # Set first time password
    $rbLog.WriteLogEntry($RunbookName,"First time password set to $pwd")

    # Pass hashtable and create AD User object, passthru result
    $user = New-ADUser @params
    $user.pdw = "$pwd"

    $rbLog.WriteLogEntry($RunbookName,"Successfully created account: $($user.DistinguishedName)")

     # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Account' = @{'Values'=$user}
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'Account' = $null
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
