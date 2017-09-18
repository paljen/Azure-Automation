 
<#
.DESCRIPTION
    A brief description on what is going on in the runbook,
    
    Core runbooks 
    •	Core functionality used in components and control runbooks.
    •	Does not connect to azure resource manager

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
    
    <#
    CODE
    #>

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'ObjectCount' = 1
    }
}

catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
    $Log.Add($instance.WriteLogEntry($RunbookName,"Exception Caught at line $($_.InvocationInfo.ScriptLineNumber), $excep")) | Out-Null

    # If you throw the error 
    if($_.Exception.WasThrownFromThrowStatement){
        $status = "failed"
    }
    else{
        $status = "warning"
    }

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = $status
                        'Message' = $excep
                        'ObjectCount' = 0
    }
    
    Write-Error $status -ErrorAction Continue
}
finally
{
    # Add Trace and runbook variables to the output object
    $props.Add('Trace',$trace)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
} 