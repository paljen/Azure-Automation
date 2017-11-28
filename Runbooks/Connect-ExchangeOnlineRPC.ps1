
<#
.DESCRIPTION
    Connect to exchange online

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
    Note     : 1.0 - 21-02-2017, Admin-PJE, Initial runbook development
    Note     : 1.1 - 29-02-2017, Admin-SKJA, minor bug fix when creating a new session
#>

[CmdletBinding()]

Param(

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Connect-ExchangeOnlineRPC"

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

    try{
        Get-AzureRmAutomationAccount | Out-Null
    }
    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        
        $rbLog.WriteLogEntry($conn)

        if($conn.status -ne "Success"){
            Throw "Connecting to Azure failed"
        } 
    }
          
    # Import Modules and setup implicit remoting
    $Credentials = Get-AutomationPSCredential -Name "AzService-ExchangeAutomation"

    $uri = Get-AutomationVariable -Name "ConnectionURI-ExchangeOnlineRPC"
    $session = New-PSSession -Name $RunbookName -ConfigurationName Microsoft.Exchange -ConnectionUri $uri -Credential $Credentials -Authentication Basic -AllowRedirection

    #BUG Fix, I have seen the first connection fail from time to time on prem, running again usually works.. /SKJA
    if (!$session) {
        $session = New-PSSession -Name $RunbookName -ConfigurationName Microsoft.Exchange -ConnectionUri $uri -Credential $Credentials -Authentication Basic -AllowRedirection
    }

    $module = Import-PSSession $session -DisableNameChecking -AllowClobber

    if($session.Availability -eq "Available" -and $module -ne $null){
        $rbLog.WriteLogEntry($RunbookName,"Successfully Imported CmdLets from $($session.ConfigurationName)")
    }
    else{
        Throw "Failed: Session either broken or no CmdLets imported"
    }
       
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Successfully Imported Module $($module.name)"
                        'Connect' = @{'Module'=$module;'Session'=$session}
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'Connect' = @{'Module'=$module;'Session'=$session}
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
