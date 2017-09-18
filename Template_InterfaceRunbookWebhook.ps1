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

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal. Use Write-Verbose 
   in the runbook to write to verbose stream#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = ""

# If runbook was called from Webhook, WebhookData will not be null.
if ($WebhookData -eq $null) { 
    Write-Error "this runbook is designed to be triggered from a webhook"  
}#>

try
{
    #region Initialize Log
    $repo = Get-AutomationVariable -Name Repository
    . $repo\Classes\Log.ps1

    # Initialize Log
    [Array]$instance = [RunbookLog]::New()

    # Clone Logging Array to ArrayList to utalize array methods
    [System.Collections.ArrayList]$Log = $instance.Clone()

    # Clear Cloned array
    $Log.clear()
    #endregion

    # Initialize trace output stream, if the runbook is run in Azure the computername will return CLIENT
    $Log.Add($instance.WriteLogEntry($RunbookName,"Running on ($env:COMPUTERNAME)")) | Out-Null
    
    # Optional - Connect to Azure Resource Manager, ignore if this is called from an Control runbook 
    # Where connection already has been initialized with the variable `$conn
    try{
        Get-AzureRmAutomationAccount | Out-Null
    }
    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        
        # Recieve log from sub runbook
        foreach ($i in $conn.Trace){
            $Log.Add($instance.WriteLogEntry($i.RunbookName,$i.Message)) | Out-Null
        }

        if($conn.status -ne "Success"){
            Throw "Error - Connecting to Azure failed"
        } 
    }

    # Collect properties of WebhookData
    $WebhookName    =   $WebhookData.WebhookName
    $WebhookHeaders =   $WebhookData.RequestHeader
    $WebhookBody    =   $WebhookData.RequestBody

    # Convert webhookbody to hashtable
    $Data = ConvertFrom-Json $WebhookBody

    <# Local Test Input Example, JSON format
    $WebhookBody = @"
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

    <#
    CODE

    #example code to extract paramters if a nested object is passed
    foreach ($paramName in  (($data.parameters | Get-Member -MemberType NoteProperty).Name))
    {
        $Parameters += @{"$paramName" = $data.parameters.$paramName}
    }

    #>
   

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'ObjectCount' = 1}
}

catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
    $Log.Add($instance.WriteLogEntry($RunbookName,"Exception Caught at line $($_.InvocationInfo.ScriptLineNumber), $excep")) | Out-Null

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = $status
                        'Message' = $excep
                        'ObjectCount' = 0
    }
    
    Write-Error $excep -ErrorAction Continue
}
finally
{
    # Remove session if needed, change if needed
    try{
        Remove-PSSession -name $($modules[1].Connect.Session.Name)
        $Log.Add($Instance.WriteLogEntry($RunbookName,"Removing session $($modules[1].Connect.Session.Name)")) | Out-Null

    }
    catch{
        $Log.Add($Instance.WriteLogEntry($RunbookName,"Session does not exist $($modules[1].Connect.Session.Name)")) | Out-Null
    }

    # Add Trace and runbook variables to the output object
    $props.Add('Trace',$trace)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    # optional, use Send-Email to send email or sms notifications, for sms use EmailAddressTo file with +45xxxxxxxx@sms.ecco.local
    # Body parameter has to be an object
    $email = .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Daily Report $RunbookName" -Body $Out -AsHtml

    Write-Output $out
} 