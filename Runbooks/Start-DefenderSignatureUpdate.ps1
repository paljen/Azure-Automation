  
<#
.DESCRIPTION
    A brief description on what is going on in the runbook

.INPUTS
    NA

.OUTPUTS
    NA

.NOTES
    Version:        1.0.0
    Author:			
    Creation Date:	
    Purpose/Change:	Initial runbook development
#>

Param(
    [String]$ServerName
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue" #Continue = enable
$RunbookName = "Start-DefenderSignatureUpdate"

try
{
    # Initialize trace output stream
    $trace = ""

    # Logic goes here
    ##
    $trace += "$([DateTime]::Now.ToString())`tStarting signature update on server: $($ServerName)`n"
    ##
    
    Invoke-Command -ComputerName $ServerName -ScriptBlock {import-module Defender; Update-MPSignature}
    
    $trace += "$([DateTime]::Now.ToString())`tFinished updating signatures on server: $($ServerName)`n"
       
    # Return values used for further processing
    $props = @{'Status' = "Success"
               'Message' = "Workflow Finished Successfully"
               'ObjectCount' = 1}
}

catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
    $trace += "$([DateTime]::Now.ToString())`tException Caught at line $($_.InvocationInfo.ScriptLineNumber), $excep`n"

    # If you throw the error 
    if($_.Exception.WasThrownFromThrowStatement)
    {$status = "failed"}
    else
    {$status = "warning"}

    # Return values used for further processing
    $props = @{'Status' = $status
               'Message' = "Error"
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
