
<#
.DESCRIPTION
    Force an Azure AD Syncronization

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
    Note     : 1.0 - 17-03-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(
    
    [Parameter(Mandatory=$true)]
    [String]$ComputerName,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Delta", "Initial")]
    [String]$SyncType
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Invoke-AzureADSync"

try
{
    # Test data
    #$computername = ""
    #$synctype = "delta"

    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "`$RunbookName variable not initialized"}

    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")
           
   # Azure AD Syncronization
    $out = Invoke-Command -ComputerName $($ComputerName) -ScriptBlock {
        Import-Module ADSync

        # Initialize state to failed
        $state = "Failed"
        
        # Test if synctype is valid
        switch ($using:SyncType){
            "Delta" {$attempts = 3}
            "Initial" {$attempts = 1}
            Default {Throw "$($using:SyncType) not a valid synctype"}
        }

        $status = @{Attempts=0;Success=0;Failed=0}
        
        try{
            if((Get-ADSyncConnectorRunStatus).runstate -isnot [Object]){               
                # Waiting for AD Connect to syncronize
                for ($i = 0; $i -lt $attempts; $i++){ 
                    try{
                            $status.attempts++

                            Start-Sleep 10
                            Start-ADSyncSyncCycle -PolicyType $using:SyncType | Out-Null

                            $status.Success++
                                                          
                            do{
                                Start-sleep 10
                            }
                            until ((Get-ADSyncConnectorRunStatus).runstate -isnot [Object])
                    }
                    catch{
                        $status.Failed++
                    }
                }

                # If all 3 attempts is success set state to success, the state will be warning if 1 sync fails
                if($status.Success -eq $attempts){
                    $state = "Success"
                    $message = "Azure AD $using:SyncType sync completed successfully"
                }
                else{
                    $state = "Warning"
                    $message = "Azure AD $using:SyncType sync completed with a warning"
                }

                
                
                @{'Message'=$message;'State'=$state;'Trace'=$trace;'Status'=$status}
            }
            else{
                # State Warning will be rerun
                $state = "Failed"
                Throw "Connector: $((Get-ADSyncConnectorRunStatus).ConnectorName) is busy"
            }
        }
        catch{
            @{'Message'=$_.Exception.Message;'State'=$state;'Trace'=$trace;'Status'=$status}
        }
    }

    $rbLog.WriteLogEntry($RunbookName, $out.message)

    if($out.State -eq "Failed"){        
        Throw $out.Message
    }
    
    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = $out.state
                        'Message' = "Runbook Finished Successfully"
                        'AADSync' = @{'Values'=$out}
                        'ObjectCount' = 1}
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'AADSync' = @{'Values'=$out}
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
