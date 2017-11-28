
<#
.DESCRIPTION
    Crteate new service now record

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
    [String]$Table,

    [Parameter(Mandatory=$true)]
    [Hashtable]$Content
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "New-ServiceNowItem"

try
{
    <# Data used for testing and debugging, adjust to fit needs
    $Table = "u_azure_automation_runbook"
    $content = @{}
    $content.u_name = "BlaTest"
    #>

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
           
    $cred = Get-AutomationPSCredential -Name "ServiceNow Admin"
    $snInstance = Get-AutomationVariable -Name "ServiceNow URL"

    # HTTP URL to record
    if($staging){
        $uri = "https://$snInstance/api/now/import/$table"
    }
    else{
        $uri = "https://$snInstance/api/now/table/$table"
    }
   
    # convert hashtable to JSON
    $body = ConvertTo-Json $Content

    # Define method and content data type
    $contentType = "application/json"
    $method = "Post"

    # Send HTTP request
    $response = Invoke-WebRequest -Method $method -Uri $uri -Body $body -ContentType $contentType -Credential $cred -UseBasicParsing

    if($response.RawContentLength -eq 0)
    {
        Throw "Error - Record not created, StatusCode $($response.StatusCode)"
    }

    $item = ($response.Content | ConvertFrom-JSON).Result

    $rbLog.WriteLogEntry($RunbookName,"Created Record with Sys_Id $($item.sys_id) in table $table, StatusCode: $($response.statusCode)")
      
    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Item' = $item
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'Item' = $null
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
