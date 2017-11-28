
<#
.DESCRIPTION
    Connects to SCOM 2016 On Premise

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
    Note     : 1.0 - 03-06-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Import-SCCMComputerInformation"

try
{
    <#
    $params = @{}
    $params.Add('Name',$Name)
    $params.Add('MAC',$MAC)
    $params.Add('SCCMServer',"DKHQSCCM02")#>

    $params = @{}
    $params.Add('Name','PJETESTCOMP1')
    $params.Add('MAC','00:11:22:33:44:55')
    $params.Add('SCCMServer',"DKHQSCCM02")#>

    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "`$RunbookName variable not initialized"}

    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")
           
    $session = New-PSSession -ComputerName $params.SCCMServer

    $rbLog.WriteLogEntry($RunbookName, "Invoking SCCM task on server $($params.SCCMServer)")
    $rbLog.WriteLogEntry($RunbookName, "Session ID: $($session.Id)")
    $rbLog.WriteLogEntry($RunbookName, "Name: $($session.Name)")
    $rbLog.WriteLogEntry($RunbookName, "ComputerName: $($session.ComputerName)")
    $rbLog.WriteLogEntry($RunbookName, "ComputerType: $($session.ComputerType)")
    $rbLog.WriteLogEntry($RunbookName, "State: $($session.State)")
    $rbLog.WriteLogEntry($RunbookName, "Availability: $($session.Availability)")

    $out = Invoke-Command -Session $session -ScriptBlock{
        try{
            Import-Module ConfigurationManager

            Set-Location P01:
            #cd P01:

            if(!(Get-CMDevice -Name $($using:params.Name))){
                Import-CMComputerInformation -CollectionName "All Systems" -ComputerName $using:params.Name -MacAddress $using:params.MAC

                $status = "Success"
                $message = "Successfully imported Computer $($using:params.Name)" 
            }
            else{
                $status = "Warning"
                Throw "Could not import computer, $($using:params.Name) already exists"
            }
        }
        catch{
            $status = "Failed"
            $message = $_.Exception.Message
        }
        finally{
            
            @{'Status'=$status;'Message'=$message}
        }
    }

    # Check the status
    if($out.Status -eq "Failed"){        
        Throw $out.Message
    }

    $rbLog.WriteLogEntry($RunbookName, $out.Message)
       
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
    try{
        Remove-PSSession -name $session.Name
        $rbLog.WriteLogEntry($RunbookName,"Removing session $($session.Name)")
    }
    catch{
        $rbLog.WriteLogEntry($RunbookName,"Session does not exist $($session.Name)")
    }

    $rbLog.WriteLogEntry($RunbookName,"Runbook finished - total runtime: $((([DateTime]::Now) - $StartTime).TotalSeconds) Seconds")
    $rbLog.Log.GetEnumerator() | foreach { Write-Verbose "$($_.RunbookName), $($_.Message), $($_.TimeStamp)" }

    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}
