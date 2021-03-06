
<#
.DESCRIPTION
    Retrive LAPS password on remote computer

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
    Version  : 1.1
    Template : Component
    tVersion : 2.2
    Author   : Palle Jensen (PJE)		
    Note     : {[Major.Minor]} - {Date}, {Username}, {Description}
    Note     : 1.0 - 02-09-2017, Admin-PJE, Initial runbook development
    Note     : 1.1 - 02-09-2017, Admin-PJE, Added the posibility to return output as JSON 
#>

[CmdletBinding()]

Param(
    
    [Parameter(Mandatory=$true)]
    [String]$Computer,

    [Parameter(Mandatory=$false)]
    [Boolean]$ConvertToJson = $false

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Get-ADLAPSPassword"

try
{
    #$params = @{}
    #$params.add('Identity',$UserPrincipalName)
    #$params.add('DomainController',$DomainController)

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
    $modules += Import-Module ActiveDirectory -PassThru

    # Throw error if one module dont get imported
    if($modules[0].count -lt 1)
    {
        Throw "Error - One or more modules was not imported"
    }
    
    $cred = Get-AutomationPSCredential -Name "Service-LAPSClients"
    $comp = Get-ADComputer $computer -Properties ms-Mcs-AdmPwd -Credential $cred | select @{l='ComputerName';e={$_.Name}}, @{l='LAPSPassword';e={$_."ms-Mcs-AdmPwd"}}

    $rbLog.WriteLogEntry($RunbookName, "Successfully retrived LAPS password on computer $computer")
    
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Computer' = $comp
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'Computer' = $null
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

    if($ConvertToJson){
        Write-Output $out | ConvertTo-Json}
    else{
        Write-Output $out}
}
