param ( 
        [object]$WebhookData
)

$RunbookName = "Interface-SCOM"

# If runbook was called from Webhook, WebhookData will not be null.
if ($WebhookData -eq $null) { 
    Write-Error "this runbook is designed to be triggered from a webhook"  
}#>


# Local Test Input Example
<#$WebhookBody = @"
{
  "alarmtype": "",
  "andet": "",
  "runbookName": "Caller",
  "stage": 1,
  "parameters": {
         "Name":"Scarlett",
         "Number":77,
         "SayGoodbye":"true"
      }
}
"@
#>

#$conn = .\Connect-AzureRMAutomation.ps1

# Collect properties of WebhookData
$WebhookName    =   $WebhookData.WebhookName
$WebhookHeaders =   $WebhookData.RequestHeader
$WebhookBody    =   $WebhookData.RequestBody
#>

$Data = ConvertFrom-Json $WebhookBody

try
{
    $trace = ""

    # Connect to Azure Resource Manager, ignore if this is called from an Control runbook 
    # Where connection already has be initialized with the variable `$conn
    try{
        Get-AzureRmAutomationAccount | out-null
        $trace += "$([DateTime]::Now.ToString())`tAlready Logged into Azure Resource Manager, $($conn.status)"
    }
    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        $trace += "$($conn.Trace)"

        if($conn.status -ne "Success")
        {
           
            Throw "Error - Connecting to Azure failed"
        } 
    }

    Write-verbose "Successfully Logged into Azure!"

    #region Import Modules and connections
    $modules = @()
    $modules += .\Connect-SCOMOnPrem.ps1

    $trace += "$($modules[0].Trace)"

    # Throw error if one module dont get imported
    if($modules[0].ObjectCount -lt 1)
    {
        Throw "Error - One or more modules was not imported"
    }
    #endregion

    $trace += "$([DateTime]::Now.ToString())`tGetting SCOM Alert with ID: $($Data.AlertId)`n"
    try
    {
        $Alert = Get-SCOMAlert -Id $Data.AlertId
        if ($Alert) {
            $trace += "$([DateTime]::Now.ToString())`tFound SCOM Alert with ID: $($Data.AlertId)`n"
        }
        else {
            Throw "No SCOM Alert found!"
        }
    }
    catch
    {
        $trace += "$([DateTime]::Now.ToString())`t$($_.exception.message)`n"
    }
    
    #region Alert Logic
    ####### Alert Logic Handling goes in here... #######
    $AlertHandling = "N/A"

    ### Auto resolve alerts
    $AutoResolveAlerts = @(
            "Power Shell Script failed to run", 
            "Database consistency check performed with no errors",
            "MSSQL 2014: Database consistency check performed with no errors",
            "Operations Manager failed to start a process",
            "Operations Manager Failed to convert performance data",
            "Application Pool worker process is unresponsive",
            "Application Pool worker process terminated unexpectedly")

    if ($Alert.Name -in $AutoResolveAlerts -and $Alert.ResolutionState -ne 255) {
        $AlertHandling = "AutoResolve"
        $trace += "$([DateTime]::Now.ToString())`tAuto-resolving SCOM Alert with ID: $($Data.AlertId)`n"
        Invoke-Command -Session $modules[0].Connect.Session -ArgumentList @($Alert) -ScriptBlock {import-module OperationsManager; Get-SCOMAlert -id $args[0].Id | Set-SCOMAlert -ResolutionState 255 -Comment "Azure Automation: Auto resolved alert" }
    }


    $AutomatedRecoveryAlerts = @()
    $AutomatedRecoveryAlerts += [PSCustomObject]@{AlertName = "Windows Defender Scan Alert"; RunbookName = "Start-DefenderQuickScan"; RBParameterName = "ServerName"; RBParameterValue = "PrincipalName"}
    $AutomatedRecoveryAlerts += [PSCustomObject]@{AlertName = "Windows Defender Definitions Alert"; RunbookName = "Start-DefenderSignatureUpdate"; RBParameterName = "ServerName"; RBParameterValue = "PrincipalName"}


    if ($Alert.Name -in $AutomatedRecoveryAlerts.AlertName -and $Alert.ResolutionState -ne 255) {
        #Invoke the runbook with the Alert Property named
        $Action = $AutomatedRecoveryAlerts | ? {$_.AlertName -eq $Alert.Name}
        if ($action.RBParameterName -ne "") {
            #Start the runbook
            $RBParameters = @{$Action.RBParameterName = $Alert."$($Action.RBParameterValue)"}
            $params = @{
                'AutomationAccountName' = $conn.AutomationAccount.AutomationAccountName
                'Name' = $Action.RunbookName
                'ResourceGroupName' = $conn.AutomationAccount.ResourceGroupName
	            'Parameters' = $RBParameters
			    'RunOn' = 'ECCO-DKHQ'
                'Wait' = $true
                'MaxWaitSeconds' = 600
            }

            $trace += "$([DateTime]::Now.ToString())`tStarting Recovery runbook: $($Action.RunbookName)`n"

            $JobResult = Start-AzureRMAutomationRunbook @params
            #$trace += "$([DateTime]::Now.ToString())`tRunbook result:`n"
            $trace += "$($JobResult.Trace)`n"

            
        }
        $AlertHandling = "AutomticRecovery"
    }

    ### If no alert handling options found, write that to trace before exit.
    If ($AlertHandling -eq "N/A") {
        $trace += "$([DateTime]::Now.ToString())`tNo alert routing found for this alert, exiting.`n"
    }
    ####################################################
    #endregion


    # Return values to component runbook
    $props = @{'Status' = "Success"
               'Message' = "Workflow Finished Successfully"
               'ObjectCount' = 1
               'AlertHandling' = $AlertHandling
               'AlertDescription' = "$($Alert.Description)"
               'AlertPrincipalName' = "$($Alert.PrincipalName)"
               'AlertResolutionState' = "$($Alert.ResolutionState)"
               'AlertMonitoringObjectPath' = "$($Alert.MonitoringObjectPath)"}
}
catch
{
    $trace += "$([DateTime]::Now.ToString())`tException Caught at line $($_.InvocationInfo.ScriptLineNumber)`n"

    if($_.Exception.WasThrownFromThrowStatement)
    {$status = "failed"}
    else
    {$status = "warning"}

    # Return values to component runbook
    $props = @{'Status' = $status
               'Message' = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
               'ObjectCount' = 0}
    
    Write-Error $status
}
finally
{
    $props.Add('Trace',$trace)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Remove-PSSession -name $($modules[0].Connect.Session.Name)

    Write-Output $out
}   
