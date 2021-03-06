
<#
.DESCRIPTION

    Send Email

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
	[string]$EmailAddressTO,

    [Parameter(Mandatory=$false)]
	[string]$EmailAddressCC,

    [Parameter(Mandatory=$true)]
	[string]$Subject,

    [Parameter(Mandatory=$true)]
	$Body,
    
    [Parameter(Mandatory=$false)]
	[Switch]$AsHtml
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Send-Email"

try
{
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
           
    $Cred = Get-AutomationPSCredential -Name "AzService-ExchangeAutomation"
         
    $Message = New-Object System.Net.Mail.MailMessage  
    $Message.From = $cred.UserName 
    $Message.replyTo = $cred.UserName
    $Message.To.Add($EmailAddressTO)

    if ($EmailAddressCC) { 
        $Message.CC.Add($EmailAddressCC) }

    $Message.Subject = $Subject
    $Message.IsBodyHtml = $true
    $Message.SubjectEncoding = ([System.Text.Encoding]::UTF8)
    $Message.Body = $body 
    $Message.BodyEncoding = ([System.Text.Encoding]::UTF8)
        
    if ($hostname -ne "CLIENT") {
        $rbLog.WriteLogEntry($RunbookName,"Send mail using mailgate.ecco.com")
        $SmtpClient = New-Object System.Net.Mail.SmtpClient 'mailgate.ecco.com', 25
    }

    else {
        $rbLog.WriteLogEntry($RunbookName,"Send mail using smtp.office365.com")
        $SmtpClient = New-Object System.Net.Mail.SmtpClient 'smtp.office365.com', 587
        $SmtpClient.EnableSsl   = $true  
    }

    $SmtpClient.Credentials = $Cred 
    $SmtpClient.Send($Message)
           
    $rbLog.WriteLogEntry($RunbookName,"E-mail send to $($EmailAddressTO) with subject: $($Subject)")
      
    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
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
