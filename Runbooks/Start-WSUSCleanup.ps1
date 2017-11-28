<#
.DESCRIPTION
    A brief description on what is going on in the runbook

    Component / Script runbooks
    •	Modular, reusable – single purpose runbooks. (Tag: Component)
    •	Non modular, made for a specific purpose (Tag: Script)
    •	Uses Core runbooks to connect to resources
    •	Can be initiated from all higher tier runbooks (Interfaces, Controllers)
    •	Connects to azure resource manger if needed

.INPUTS
    NA

.OUTPUTS
    [Object]

.NOTES
    Version:        1.0.0
    Author:			admin-pje
    Creation Date:	
    Purpose/Change:	Initial runbook development
#>

Param(

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal. Use Write-Verbose 
   in the runbook to write to verbose stream#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Start-WSUSCleanup"

try
{
    Function Add-TraceEntry($string)
    {
        "$([DateTime]::Now.ToString())`t$string`n"        
    }

    # Initialize trace output stream, if the runbook is run in Azure the computername will return CLIENT
    $trace = ""
    $trace += Add-TraceEntry "$RunbookName Running on ($env:COMPUTERNAME)"

    # Optional - Connect to Azure Resource Manager, ignore if this is called from an Control runbook 
    # Where connection already has been initialized with the variable `$conn
    try{
        Get-AzureRmAutomationAccount | Out-Null
        $trace += Add-TraceEntry "Already Logged into Azure Resource Manager, $($conn.status)"
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

    $UseSSL = $False
    $PortNumber = 8530
    $Server = "dkhqsccm02"

    $cmd = Invoke-Command -ComputerName $server -ScriptBlock {
        # Add UpdateServices .NET Framework
        Add-Type -Path "C:\Program Files\Update Services\API\Microsoft.UpdateServices.Administration.dll"
        $trace += Add-TraceEntry "Add Microsoft.UpdateServices Framework "

        # Setup WSUS connection
        $WSUSConn = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($Using:Server,$Using:UseSSL,$Using:PortNumber)
        $trace += Add-TraceEntry "Get Update Server $(($wsusconn).WebServiceUrl)"

        # Declare cleanup scope
        $scope = New-Object Microsoft.UpdateServices.Administration.CleanupScope
        $scope.CleanupObsoleteComputers = $True
        $scope.CleanupObsoleteUpdates = $True
        $scope.CleanupUnneededContentFiles = $True
        $scope.CompressUpdates = $True
        $scope.DeclineExpiredUpdates = $True
        $scope.DeclineSupersededUpdates = $True
        $trace += Add-TraceEntry "Declared CleanUp Scope $(($scope | select *))"

        # Execute WSUS Cleanup
        $task = $WSUSConn.GetCleanupManager()
        $results = $task.PerformCleanup($scope)
        #$trace += Add-TraceEntry "Preform CleanUp)"
        
        # Create report object
        $report = [Ordered]@{'SupersededUpdatesDeclined' = $results.SupersededUpdatesDeclined
                             'ExpiredUpdatesDeclined' = $results.ExpiredUpdatesDeclined
                             'ObsoleteUpdatesDeleted' = $results.ObsoleteUpdatesDeleted
                             'UpdatesCompressed' = $results.UpdatesCompressed
                             'ObsoleteComputersDeleted' = $results.ObsoleteComputersDeleted
                             'DiskSpaceFreed' = $results.DiskSpaceFreed
        }

        # Prepare output object
        $out = New-Object -TypeName PSObject -Property @{'Report'= New-Object -TypeName PSObject -Property $report}
        Write-Output $out
    }

    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Report' =  $cmd.report}
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
    $props = [Ordered]@{'Status' = $status
                        'Message' = $excep
                        'Report' = $cmd.report}
    
    Write-Error $status
}
finally
{
    # optional, use Send-Email to send email or sms notifications, for sms use EmailAddressTo file with +45xxxxxxxx@sms.ecco.local
    $email = .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Runbook - $RunbookName Status" -Body $props.Report -AsHtml
    $trace += "$($email.Trace)"

    $props.Add('Trace',$trace)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}  
