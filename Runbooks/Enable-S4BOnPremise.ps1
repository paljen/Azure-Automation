
<#
.DESCRIPTION
    Enable on-premise skype for business

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
    Note     : 1.0 - 19-09-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(
    
    [Parameter(Mandatory=$true)]
    [String]$UserPrincipalName,

    [Parameter(Mandatory=$true)]
    [String]$RegistrarPool,

    [Parameter(Mandatory=$true)]
    [String]$DomainController

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Enable-S4BOnPremise"

try
{
    <#  Test Data Create hashtable with parameters
    $params = @{}
    $params.Add('RegistrarPool',"DKHQUCPOOL02.PRD.ECCOCORP.NET")
    $params.add('SipAddressType',"UserPrincipalName")
    $params.Add('DomainController',"dkhqdc02.prd.eccocorp.net")
    $params.Add('Identity',"Skypetest@ecco.com")
    $params.add('PassThru',$true)#>

    # Create hashtable with parameters
    $params = @{}
    $params.Add('RegistrarPool',$RegistrarPool)
    $params.add('SipAddressType', 'UserPrincipalName')
    $params.Add('DomainController',"dkhqdc02.prd.eccocorp.net")
    $params.Add('Identity',$UserPrincipalName)
    $params.add('PassThru',$true)#>

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
    $modules += .\Connect-S4BOnPremise.ps1

    $rbLog.WriteLogEntry($modules[0])

    if($modules[0].ObjectCount -lt 1)
    {
        Throw "failed - One or more modules was not imported"
    }

     # Create hashtable with parameters
    $params = @{}
    $params.add('Identity',$UserPrincipalName)
    $params.add('RegistrarPool',$RegistrarPool)
    $params.add('SipAddressType',"UserPrincipalName")
    $params.add('DomainController',$DomainController)
    $params.add('PassThru',$true)

    $csuser = Enable-CsUser @params
    $rbLog.WriteLogEntry($RunbookName,"SkypeForBusiness account $($csuser.SamAccountName) enabled: $($csuser.SipAddress)")
    
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Account' = @{'Values'=$csuser}
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
    Remove-PSSession -name $($modules[0].Connect.Session.Name) -ErrorAction SilentlyContinue

    $rbLog.WriteLogEntry($RunbookName,"Runbook finished - total runtime: $((([DateTime]::Now) - $StartTime).TotalSeconds) Seconds")
    $rbLog.Log.GetEnumerator() | foreach { Write-Verbose "$($_.RunbookName), $($_.Message), $($_.TimeStamp)" }

    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}
