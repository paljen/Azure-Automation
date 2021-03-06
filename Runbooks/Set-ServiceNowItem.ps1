
<#
.DESCRIPTION

    Update ServiceNow record

    Runbook Tagging
    •	Modular, reusable – single purpose runbooks. - Tag: Component
    •	Modular, reusable – single purpose runbooks used in Components - Tag: Core
    •	Non modular, made for a specific purpose - Tag: Script   
    •	Flow specific runbooks - Tag: Controller
    •	Integration runbooks combined with webhooks - Tag: Interface

.PARAMETER  Table
	ServiceNow table name

.PARAMETER  Content
	Data to be updated as hashtable

.PARAMETER  SysId
	The sysId of the record

.PARAMETER  Method
	REST HTTP Methods to be used, allowed are PUT and PATCH

.OUTPUTS
    [Object]

.NOTES
    Version  : 1.0
    Template : Component
    tVersion : 2.2
    Author   : Palle Jensen (PJE)		
    Note     : {[Major.Minor]} - {Date}, {Username}, {Description}
    Note     : 1.0 - 21-09-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(

    [Parameter(Mandatory=$true)]
    [String]$Table,
    
    [Parameter(Mandatory=$true)]
    [Hashtable]$Content,
    
    [Parameter(Mandatory=$true)]
    [String]$SysId,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Put", "Patch")]
    [String]$Method
    
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Set-ServiceNowItem"

try
{
    <# Test Data
    $sysid = "fa05eb6bdbd14b0096e8f7461d961975"
    $table = "u_azure_automation_runbook"
    $content = @{'u_description' = "blabla"}
    $method = "Put"
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
        
        # Write Log entries from sub runbook
        $rbLog.WriteLogEntry($conn)

        if($conn.status -ne "Success"){
            Throw "Error - Connecting to Azure failed"
        } 
    }

    $cred = Get-AutomationPSCredential -Name "ServiceNow Admin"
    $snInstance = Get-AutomationVariable -Name "ServiceNow URL"

    $uri = "https://$snInstance/api/now/table/$table/$sysid"
    
    $body = ConvertTo-Json $Content

    $contentType = "application/json"

    $response = $null
    $response = Invoke-WebRequest -Method $method -Uri $uri -Body $body -ContentType $contentType -Credential $cred -UseBasicParsing

    if($response.StatusCode -ne 200 -and $response.StatusCode -ne 201 -and $response.StatusCode -ne 204)
    {
        Throw "Response returned statuscode: $($response.StatusCode)"
    }

    $rbLog.WriteLogEntry($RunbookName,"Updated Record with Sys_Id $sysId in table $table, StatusCode: $($response.statusCode)")
       
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Item' = ($response.Content | ConvertFrom-JSON).Result
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
