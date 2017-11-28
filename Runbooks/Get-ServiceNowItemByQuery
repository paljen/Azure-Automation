
<#
.DESCRIPTION
    Query data from table in ServiceNow

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

    [Parameter(Mandatory=$false)]
    [String]$Query,

    [Parameter(Mandatory=$false)]
    [Int]$Limit
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Get-ServiceNowItemByQuery"

try
{
    <# Data used for testing and debugging, adjust to fit needs
    $table = "u_azure_automation_runbook"
    #$Query = "sys_updated_on > 2017-01-08 21:21:21"
    #$Limit = 1
    #>

    <# Data used for testing and debugging, adjust to fit needs
    $table = "cmdb_ci_computer"
    $Query = "osNOT LIKEServer^osNOT LIKELinux^install_status=1^nameISNOTEMPTY"
    $Limit = 20000
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

    $uri = "https://$snInstance/api/now/table/$table"

    # Populate the query
    $Body = @{}
    if($Limit){
        $Body.sysparm_limit = $Limit
        $rbLog.WriteLogEntry($RunbookName, "Records returned is limited to $limit")
    }
    if($Query){
        $Body.sysparm_query = $Query
        $rbLog.WriteLogEntry($RunbookName, "Query table with - $query")
    }

    $contentType = "application/json"
    $method = "Get"

    $response = $null
    $response = Invoke-WebRequest -Method 'get' -Uri $uri -Body $body -ContentType 'application/json' -Credential $Cred -UseBasicParsing

    $rbLog.WriteLogEntry($RunbookName, "Querying Service Now: 'URI'=$uri;'Method'=$method")

    if($response.StatusCode -ne 200 -and $response.StatusCode -ne 201 -and $response.StatusCode -ne 204)
    {
        Throw "Response returned statuscode: $($response.StatusCode)"
    }
    
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Item' = ($response.Content | ConvertFrom-JSON).Result
                        'ObjectCount' = 1}
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
