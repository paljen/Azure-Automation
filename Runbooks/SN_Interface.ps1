<#
.DESCRIPTION
    A brief description on what is going on in the runbook,
    
    Interface runbooks 
    •	Interfaces with other systems through webhooks
    •	This runbook is concidered the highest runbook tier

.INPUTS
    [Object]

.OUTPUTS
    [Object]

.NOTES
    Version:        1.0.0
    Author:			
    Creation Date:	
    Purpose/Change:	Initial runbook development
#>

param ( 
        [object]$WebhookData
)

# If runbook was called from Webhook, WebhookData will not be null.
if ($WebhookData -eq $null) { 
    Write-Error "this runbook is designed to be triggered from a webhook"  
}#>

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal. Use Write-Verbose 
   in the runbook to write to verbose stream#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = ""

# Local Test Input Example, JSON format
<#$WebhookBody = @"
{
  "table": "sc_req_item",
  "sysid": "9abcf0a6db98360096e8f7461d9619a4",
  "runbookName": "SN_Out",
  "stage": 1,
  "parameters": {
         "Name":"Scarlett",
         "Number":77,
         "SayGoodbye":"true"
      }
}
"@#>


try
{
    Function Add-TraceEntry($string)
    {
        "$([DateTime]::Now.ToString())`t$string`n"        
    }

    # Initialize trace output stream
    $trace = ""
    
    # Connect to azure resource manager
    $conn = .\Connect-AzureRMAutomation.ps1

    # Collect properties of WebhookData
    $WebhookName    =   $WebhookData.WebhookName
    $WebhookHeaders =   $WebhookData.RequestHeader
    $WebhookBody    =   $WebhookData.RequestBody
    #>

    $Data = ConvertFrom-Json $WebhookBody

    $Table = $Data.table
    $SysId = $Data.sysid
    $Stage = $Data.Stage
    $RunbookName = $Data.runbookName

    # Get Affected item
    $Item = .\Get-ServiceNowItemBySysId.ps1 -Table $Data.Table -Sysid $Data.SysId

    $Parameters = @{'SNItem'=$Item}

    foreach ($paramName in  (($data.parameters | Get-Member -MemberType NoteProperty).Name))
    {
        $Parameters += @{"$paramName" = $data.parameters.$paramName}
    }

    #Update Service Now Stage (Wait for condition)

    .\Set-ServiceNowItem.ps1 -Sysid $SysId -Table $Table -Content @{"u_stage_current" = "$Stage"} -Method Patch

    $params = @{'AutomationAccountName' = $conn.AutomationAccount.AutomationAccountName
                'Name' = $RunbookName
                'ResourceGroupName' = $conn.AutomationAccount.ResourceGroupName
	            'Parameters' = $Parameters
			    'RunOn' = 'ECCO-DKHQ'
                'Wait' = $true
                'MaxWaitSeconds' = 600}

    $JobResult = Start-AzureRMAutomationRunbook @params

    # Return values used for further processing, add properties if needed
    $props = @{'Status' = "Success"
               'Message' = "Successfully Message"
               'Job' = $JobResult
               'ObjectCount' = 1}
}

catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
    $trace += Add-TraceEntry "Exception Caught at line $($_.InvocationInfo.ScriptLineNumber), $excep"

    # If you throw the error 
    if($_.Exception.WasThrownFromThrowStatement)
    {$status = "failed"}
    else
    {$status = "warning"}

    # Return values used for further processing, add properties if needed
    $props = @{'Status' = $status
               'Message' = "Error Message"
               'Job' = $null
               'ObjectCount' = 0}
    
    Write-Error $status
}
finally
{
    # Add Trace and runbook variables to the output object
    $props.Add('Trace',$trace)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
} 
