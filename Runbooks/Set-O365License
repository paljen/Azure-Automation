
<#
.DESCRIPTION

    Assign O365 License

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
    [String]$UserPrincipalName,

    [Parameter(Mandatory=$true)]
    [String]$AssignIfLicensed,

    [Parameter(Mandatory=$true)]
    [String]$LicenseType,

    [Parameter(Mandatory=$false)]
    [String]$Location,

    [Parameter(Mandatory=$true)]
    [String]$UpdateSameLicense
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Set-O365License"

try
{
    function Mapping($in)
    {
        switch ($in)
        {
            'E1-Full' {"ecco:STANDARDPACK"}

            <#
            'ecco:STANDARDPACK' {"E1"}
            'ecco:ENTERPRISEPACK' {"E3"}
            'ecco:ENTERPRISEWITHSCAL' {"E4"}
            'ecco:ENTERPRISEPREMIUM_NOPSTNCONF' {"E5"}
            'ecco:EXCHANGESTANDARD' {"Exchange Online Plan 1"}
            'ecco:EXCHANGEARCHIVE' {"Exchange Online Archiving"}
            'ecco:VISIOCLIENT' {"Visio Pro"}
            'ecco:PROJECTCLIENT' {"Project Pro"}
            'ecco:POWER_BI_STANDARD' {"Power BI Free"}
            'ecco:ECAL_SERVICES' {"ECAL Services"}
            'ecco:MCOMEETADV' {"PSTN Conferencing"}
            'ecco:INTUNE_A_VL' {"Intune"}
            'ecco:AAD_PREMIUM' {"Azure AD Premium"}
            'ecco:GLOBAL_SERVICE_MONITOR' {"Global Service Monitor"}
            'ecco:DESKLESSPACK' {"K1"}
            'ecco:EMS' {"EMS"}
            'ecco:DESKLESS' {"StaffHub"}
            'MCOMEETADV' {"MCOMEETADV"}
            'ADALLOM_S_O365' {"Office 365 Advanced Security Management"}
            'EQUIVIO_ANALYTICS' {"eDiscovery"}
            'LOCKBOX_ENTERPRISE' {"Customer Lockbox"}
            'EXCHANGE_ANALYTICS' {"Delve Analytics"}
            'SWAY' {"Sway"}
            'ATP_ENTERPRISE' {"Exchange Online Advanced Threat Protection"}
            'MCOEV' {"Skype for Business Cloud PBX"}
            'BI_AZURE_P2' {"Power BI Pro"}
            'INTUNE_O365' {"Intune"}
            'PROJECTWORKMANAGEMENT' {"Planner"}
            'RMS_S_ENTERPRISE' {"Azure Active Directory Rights Management"}
            'YAMMER_ENTERPRISE' {"Yammer"}
            'OFFICESUBSCRIPTION' {"Office ProPlus"}
            'MCOSTANDARD' {"Skype for Business Online (Plan 2)"}
            'EXCHANGE_S_ENTERPRISE' {"Exchange Online (Plan 2)"}
            'SHAREPOINTENTERPRISE' {"SharePoint Online (Plan 2)"}
            'SHAREPOINTWAC' {"Office Online"}
            'MCOVOICECONF' {"Skype for Business Online (Plan 3)"}
            'SHAREPOINTSTANDARD' {"SharePoint Online (Plan 1)"}
            'EXCHANGE_S_STANDARD' {"Exchange Online (Plan 1)"}
            'E1'{"ecco:STANDARDPACK"}
            'E4' {"ecco:ENTERPRISEWITHSCAL"}
            'E5' {"ecco:ENTERPRISEPREMIUM_NOPSTNCONF"}
            'Intune' {"ecco:INTUNE_A_VL"}
            'Visio_Pro' {"ecco:VISIOCLIENT"}
            'Project_Pro' {"ecco:PROJECTCLIENT"}
            'Power_BI_Free' {"ecco:POWER_BI_STANDARD"}
            'ECAL_Services' {"ecco:ECAL_SERVICES"}
            'PSTN_Conferencing' {"ecco:MCOMEETADV"}
            'Azure_AD_Premium' {"ecco:AAD_PREMIUM"}
            'Global_Service_Monitor' {"ecco:GLOBAL_SERVICE_MONITOR"}
            'Exchange_Online_Plan_1' {"ecco:EXCHANGESTANDARD"}
            'Exchange_Online_Archiving' {"ecco:EXCHANGEARCHIVE"}
            'K1' {"ecco:DESKLESSPACK"}
            'EMS' {"ecco:EMS"}
            'StaffHub' {"ecco:DESKLESS"}#>
            default{"SKU Not found: $in"}
        } 
    }

    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "`$RunbookName variable not initialized"}

    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")
           
    $modules = @()
    $modules += .\Connect-MSOnline.ps1

    $rbLog.WriteLogEntry($modules[0])

    # Make sure that the modules were imported for the runspace
    if($modules[0].ObjectCount -lt 1){
        Throw "Error - One or more modules was not imported"
    }
              
    $rbLog.WriteLogEntry($RunbookName,"Successfully Connected to Microsoft Online")

    if((Get-MsolUser -UserPrincipalName $UserPrincipalName).UsageLocation -eq $null -and $Location -ne ""){
        
        #First get the MSOL user object
        Get-MsolUser -UserPrincipalName $UserPrincipalName | Set-MsolUser -UsageLocation $Location
        $rbLog.WriteLogEntry($RunbookName,"Successfully set location to $Location for user $UserPrincipalName")

    }
    else{
        $rbLog.WriteLogEntry($RunbookName,"UsageLocation for $($UserPrincipalName) is Null and Location parameter is empty")
    }   

    $lic = Set-MsolUserLicense -UserPrincipalName $UserPrincipalName -AddLicenses $(mapping("E1-Full")) | Out-Null
    #$Lic = Set-EcMsolUserLicense -UserPrincipalName $UserPrincipalName -LicenseType $LicenseType -AssignIfLicensed $AssignIfLicensed -UpdateSameLicense $UpdateSameLicense
    $rbLog.WriteLogEntry($RunbookName,"License set for user $UserPrincipalName - $Lic")
    $user = Get-MsolUser -UserPrincipalName $UserPrincipalName

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Runbook Finished Successfully"
                        'Account' = @{'Values'=$user}
                        'ObjectCount' = 1
    }
}
catch
{
    $excep = $(if($error[0].Exception -contains ("`"")){$error[0].Exception -Replace ("`"","'")}else{$error[0].Exception})
    $rbLog.WriteLogEntry($RunbookName, "Failed - Exception Caught at line $($error[0].InvocationInfo.ScriptLineNumber), $excep")

    $props = [Ordered]@{'Status' = "Failed"
                        'Message' = $excep
                        'Account' = @{'Values'=$user}
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
