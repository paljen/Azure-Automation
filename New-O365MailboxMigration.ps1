<#
.DESCRIPTION
    Migrate mailbox to Office365 (hybrid).

    The script starts connecting to Azure, MSOnline and Exchange Online.

    First there will be done some housekeeping from prior runs where move requests
    that are not in status completed are removed. 
    
    This is done to avoid having move requests that are stuck for some reason 
    and of course to clean up failed requests.

    A new move request is then made for each object (UserPrincipalName) the script takes as input.

    As a note the migration is done on the target domain (online) but on-premise credentails are 
    needed for the migration to start (prd.eccocorp.net\service-o365-uc).

.INPUTS
    Array

.OUTPUTS
    NA

.NOTES
    Version:        1.0.0
    Author:			Palle Jensen
    Creation Date:	21/02/2017
    Purpose/Change:	Initial runbook development
#>

Param(
    [Parameter(Mandatory=$true)]
    [Array]$UserprincipalName
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal. Use Write-Verbose 
   in the runbook to write to verbose stream#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "New-O365MailboxMigration"

try
{
    $repo = Get-AutomationVariable -Name Repository
    . $repo\Classes\Log.ps1

    # Initialize Log
    [Array]$instance = [RunbookLog]::New()

    # Clone Logging Array to ArrayList to utalize array methods
    [System.Collections.ArrayList]$Log = $instance.Clone()

    # Clear Cloned array
    $Log.clear()

    # if the runbook is run in Azure the computername will return CLIENT
    $Log.Add($instance.WriteLogEntry($RunbookName,"Running on ($env:COMPUTERNAME)")) | Out-Null

    # Optional - Connect to Azure Resource Manager, ignore if this is called from an Control runbook 
    # Where connection already has be initialized with the variable `$conn
     try{
        Write-verbose "Getting Azure Automation Account"
        Get-AzureRmAutomationAccount | out-null
        $Log.Add($Instance.WriteLogEntry($RunbookName,"Already Logged into Azure Resource Manager, $($conn.status)")) | Out-Null
    }

    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        
        foreach ($i in $conn.Trace){
            $Log.Add($instance.WriteLogEntry($i.RunbookName,$i.Message)) | Out-Null
        }

        if($conn.status -ne "Success"){
            Throw "Error - Connecting to Azure failed"
        } 

        Write-verbose "Successfully Logged into Azure!"
    }

    Write-verbose "Successfully Logged into Azure!"
            
    # Import Modules and setup implicit remoting, use component runbooks to setup implicit remoting
    $modules = @()
    $modules += .\Connect-MSOnline.ps1
    $modules += .\Connect-ExchangeOnline.ps1

    # Recieve log from sub runbook $modules.trace
    foreach ($i in $modules.trace){
        $Log.Add($instance.WriteLogEntry($i.RunbookName,$i.Message)) | Out-Null
    }

    # Make sure that the modules were imported for the runspace
    if($modules[0].ObjectCount -lt 1 -or $modules[1].ObjectCount -lt 1){
        Throw "Error - One or more modules was not imported"
    }

    # Migrating on-Prem user credentials
    $onpremPsw = ""
    $onpremKey = "114 68 52 220 193 142 18 14 248 152 104 9 229 250 130 102 227 214 5 216 214 223 112 30 66 73 229 38 86 87 170 182"
    $onpremPswSecure = ConvertTo-SecureString -String $onpremPsw -Key ([Byte[]]$onpremKey.Split(" "))
    $onPremCred = New-Object system.Management.Automation.PSCredential("prd.eccocorp.net\service-o365-uc", $onpremPswSecure)

    # Array to store the move requests
    $mRequest = @()

    # Migrade user to Office 365
    $UserPrincipalName | Foreach {
        try{
            $usr = $_

            $mReq = New-MoveRequest -Identity $usr -remote -remotehostname mail2.ecco.com -RemoteCredential $OnPremCred -targetdeliverydomain ecco.mail.onmicrosoft.com -BadItemLimit 500 -LargeItemLimit 10 -RequestExpiryInterval "00.23:00:00"
            
            $mReqData = [Ordered]@{'MailboxIdentity'= $($mReq.MailboxIdentity);'ExchangeGuid'=$($mReq.ExchangeGuid);'ArchiveGuid'=$($mReq.ArchiveGuid);'TotalMailboxSize'=$($mReq.TotalMailboxSize);'TotalMailboxItemCount'=$($mReq.TotalMailboxItemCount);`
                                   'TotalArchiveSize'=$($mReq.TotalArchiveSize);'TotalArchiveItemCount'=$($mReq.TotalArchiveItemCount)}
            
            $mRequest += New-Object -TypeName PSObject -Property $mReqData

            $Log.Add($instance.WriteLogEntry($RunbookName,"Move request initiated for user $($mReqData.MailboxIdentity)")) | Out-Null
        }
        catch{
            $mReqData = [Ordered]@{'MailboxIdentity'= $usr;'ExchangeGuid'=$null;'ArchiveGuid'=$null;'TotalMailboxSize'=$null;'TotalMailboxItemCount'=$null;'TotalArchiveSize'=$null;'TotalArchiveItemCount'=$null}

            $mRequest += New-Object -TypeName PSObject -Property $mReqData

            $Log.Add($instance.WriteLogEntry($RunbookName,"Move request could not be initiated for user $($mReqData.MailboxIdentity) - $($_.Exception.Message)")) | Out-Null
        }
    }
         
    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'MoveRequest' = $mRequest
                        'ObjectCount' = 1
    }
}

catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($_.Exception.Message.Contains("`"")){$_.Exception.Message.Replace("`"","'")}else{$_.Exception.Message})
    $Log.Add($instance.WriteLogEntry($RunbookName,"Exception Caught at line $($_.InvocationInfo.ScriptLineNumber), $excep")) | Out-Null

    # Return values to component runbook
    $props = [Ordered]@{'Status' = $status
                        'Message' = $excep
                        'MoveRequest' = $mRequest
                        'ObjectCount' = 0
    }
    
    Write-Error $status
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

    $props.Add('Trace',$Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}
