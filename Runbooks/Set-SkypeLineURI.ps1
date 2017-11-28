<#
.DESCRIPTION
    A brief description on what is going on in the runbook

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
    rVersion : 1.1
    tVersion : 2.1
    Author   : Admin-PJE
    Contact	 : Admin-KSK
    Note     : {[Major.Minor]} - {Date}, {Username}, {Description}
    Note     : 1.0 - 22-02-2017, Admin-PJE, Initial runbook development
    Note     : 1.1 - 22-02-2017, Admin-PJE, Updated runbook with changes from updated template
#>

Param(

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Set-SkypeLineUri"

try
{  
    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1
    . $ws\AzureAutomation\Repository\Classes\Report.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
            
    $modules = @()
    $modules += Import-Module ActiveDirectory -PassThru
    $modules += .\Connect-S4BOnPremise.ps1

    # Add trace output from component runbooks to this tracelog
    $rbLog.WriteLogEntry($modules)

    # Make sure that the modules were imported for the runspace
    if($modules[0].Count -lt 1 -or $modules[1].ObjectCount -lt 1){
        Throw "Failed - One or more modules was not imported"
    }

    $userCount = 0

    (Get-CsUser | ? {$_.EnterpriseVoiceEnabled -ne $true -and $_.LineURI -eq ""})| ForEach-Object {
        try{
            Get-ADUser -Identity $($_.DistinguishedName) -Properties Employeenumber | ForEach-Object {
            
                # Check if employeenumber is not null and employeenumber match format criteria of minimum 8 digits
                if($_.EmployeeNumber -ne $null -and $_.EmployeeNumber -match "\d{8}\d*"){
                    try{
                        $userCount++
                        Set-CsUser -Identity $_.DistinguishedName -LineURI "tel:+00$($_.Employeenumber)" -ErrorAction Ignore
                        $rbLog.WriteLogEntry($RunbookName,"User $($_.UserPrincipalName), LineURI set to `"tel:+00$($_.Employeenumber)`"")
                    }
                    catch{
                        $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
                        $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")
                    }
                }
            }  
        }
        catch{
            $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
            $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")
        }
    }

    if ($userCount -eq 0){
        $rbLog.WriteLogEntry($RunbookName, "No changes needed")
    }

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'ObjectCount' = 1}
}
catch
{
    # Add to trace on what line the error occured and the exception message
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'ObjectCount' = 0
    }

    Write-Error $excep -ErrorAction Continue
}
finally
{
    Remove-PSSession -name $($modules[1].Connect.Session.Name) -ErrorAction SilentlyContinue

    $rbLog.Log.GetEnumerator() | foreach { Write-Verbose "$($_.RunbookName), $($_.Message), $($_.TimeStamp)" }
    $rbLog.WriteLogEntry($RunbookName,"Total Runtime: $((([DateTime]::Now) - $StartTime).TotalSeconds) Seconds")

    $r = [RunbookReport]::new()
    $r.setStyle([Style]::DarkBlue)
    $r.addContent("Trace Log",$rbLog.Log.psobject.BaseObject)
    $report = $r.getReport()

    # for sms use EmailAddressTo file with +45xxxxxxxx@sms.ecco.local
    $email = .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Daily Report $RunbookName" -Body $report -AsHtml
    $rbLog.WriteLogEntry($email)

    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}
