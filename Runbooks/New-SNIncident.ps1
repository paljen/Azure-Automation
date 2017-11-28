 
<#
.DESCRIPTION
    A brief description on what is going on in the runbook

    Control runbooks 
    •	Flow control for particular use case where more components or scripts are a part of.
    •	Can be initiated from all higher tier runbooks (Interfaces, Init)
    •	Connects to azure resource manger if needed

.INPUTS
    NA

.OUTPUTS
    [Object]

.NOTES
    Version:        1.0.0
    Author:			
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
$RunbookName = ""

try
{
    Function Add-TraceEntry($string)
    {
        "$([DateTime]::Now.ToString())`t$string`n"        
    }

    # Initialize trace output stream
    $trace = ""
    $trace = Add-TraceEntry "Running on $(Hostname)"

    # Optional - Connect to Azure Resource Manager, ignore if this is called from an Control runbook 
    # Where connection already has be initialized with the variable `$conn
    try{
        Get-AzureRmAutomationAccount | out-null
        $trace += Add-TraceEntry "Already Logged into Azure Resource Manager, $($conn.status)"
    }

    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        $trace += "$($conn.Trace)"

        if($conn.status -ne "Success")
        {
            Throw "Connecting to Azure failed"
        }

        Write-verbose "Successfully Logged into Azure!"
    }
    
    # Test Data
    $table = "u_rest_inbound_incident"

    # Create rest body
    $Content = @{'caller_id'="Palle Jensen";
                 'u_customer'="Palle Jensen";
                 'u_service'="Calendar";
                 'u_supporting_service'="Email Support";
                 'description'="my phone";
                 'cmdb_ci'="DKHQCASHUB01N01";           
                 'u_notify_by'="Email";
                 'short_description'="bla";
                 'impact'=3;
                 'urgency'=3;
    }
    
    $out = .\New-ServiceNowItem.ps1 -Content $content -Table $table
    $trace += $($out.Trace)
       
    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Workflow Finished Successfully"
                        'Item' = $($out.Item)
                        'ObjectCount' = 1}
}

catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
    $trace += Add-TraceEntry "Exception Caught at line $($_.InvocationInfo.ScriptLineNumber), $excep"

    # If you throw the error 
    if($_.Exception.WasThrownFromThrowStatement)
    {$status = "warning"}
    else
    {$status = "failed"}

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = $status
                        'Message' = "Error Message"
                        'Item' = $null
                        'ObjectCount' = 0}
    
    Write-Error $status
}
finally
{
    $props.Add('Trace',$trace)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}   
