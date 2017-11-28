
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
    Version  : 1.0
    Template : Component
    tVersion : 2.2
    Author   : Palle Jensen (PJE)		
    Note     : {[Major.Minor]} - {Date}, {Username}, {Description}
    Note     : 1.0 - 21-01-2017, Admin-PJE, Initial runbook development
#>

[CmdletBinding()]

Param(

    [Parameter(Mandatory=$true)]
    [String]$Name,

    [Parameter(Mandatory=$true)]
    [String]$Givenname,

    [Parameter(Mandatory=$true)]
    [String]$Displayname,

    [Parameter(Mandatory=$true)]
    [String]$OrganizationalUnit,

    [Parameter(Mandatory=$true)]
    [String]$UserPrincipalName,

    [Parameter(Mandatory=$true)]
    [String]$SamAccountName,

    [Parameter(Mandatory=$true)]
    [String]$Alias,

    [Parameter(Mandatory=$true)]
    [String]$Location,

    [Parameter(Mandatory=$true)]
    [String]$LicenseType
    
)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal#>
$VerbosePreference = "SilentlyContinue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "New-RetailStoreAccount"

try
{
    $DomainController = "dkhqdc02.prd.eccocorp.net"

    # parameters for Runbook New-ADUserOnPremise
    $usrParams = @{}
    $usrParams.Add('Name',$Name)
    $usrParams.Add('Givenname',$Givenname)
    $usrParams.Add('Displayname',$Displayname)
    $usrParams.Add('SamAccountName',$SamAccountName)
    $usrParams.Add('UserPrincipalName',$UserPrincipalName)
    $usrParams.Add('OrganizationalUnit',$OrganizationalUnit)
    $usrParams.Add('DomainController',$DomainController)

    # Parameters for Runbook Enable-UserMailboxOnPremise
    $mbParams = @{}
    $mbParams.Add('UserPrincipalName',$UserPrincipalName)
    $mbParams.Add('PrimarySmtpAddress',$Alias)
    $mbParams.Add('Archive',$true)
    $mbParams.Add('DomainController',$DomainController)

    # Parameters for Runbook Enable-SkypeForBusinessOnPremise
    $sbParams = @{}
    $sbParams.Add('UserPrincipalName',$UserPrincipalName)
    $sbParams.Add('RegistrarPool',"DKHQUCPOOL02.PRD.ECCOCORP.NET")
    $sbParams.Add('DomainController',$DomainController)

    # Parameters for Runbook Set-O365License    
    $licParams = @{}
    $licParams.Add('UserPrincipalName',$UserPrincipalName)
    $licParams.Add('AssignIfLicensed',"false")
    $licParams.Add('UpdateSameLicense',"false")
    $licParams.Add('Location',$Location)
    $licParams.Add('LicenseType',$LicenseType)

    $sbmigparams = @{}
    $sbmigparams.Add('UserPrincipalName',$UserPrincipalName)
    $sbmigparams.Add('HostedMigrationOverrideUrl',"https://admin1e.online.lync.com/HostedMigration/hostedmigrationservice.svc")
    $sbmigparams.Add('ProxyPool',"dkhqucpool02.prd.eccocorp.net")
    $sbmigparams.Add('Target',"sipfed.online.lync.com")

    if ([String]::IsNullOrEmpty($RunbookName)) 
    {Throw "`$RunbookName variable not initialized"}

    $StartTime = Get-date

    $ws = Get-AutomationVariable -Name Workspace
    . $ws\AzureAutomation\Repository\Classes\Log.ps1
    . $ws\AzureAutomation\Repository\Classes\Report.ps1

    $FilePath = "$ws\AzureAutomation\Logs\$RunbookName.Log"

    Get-Item -Path $FilePath -ErrorAction SilentlyContinue | ? {$_.length / 1KB -gt 2048} | Rename-Item -NewName $RunbookName-$((get-date).tostring("MMddyyyyHHmm")).log

    [RunbookLog]$rbLog = [RunbookLog]::new($FilePath,$RunbookName)
    $rbLog.WriteLogEntry($RunbookName, "Runbook started")
           
    try{
        Get-AzureRmAutomationAccount | Out-Null
    }
    catch{
        $conn = .\Connect-AzureRMAutomation.ps1
        
        # Write Log entries from sub runbook
        $rbLog.WriteLogEntry($conn)

        if($conn.status -ne "Success"){
            Throw "Error - Connecting to Azure failed"
        } 
    }

    #region Execute runbook to create on-premises AD user
    $usr = .\New-ADUserOnPremise.ps1 @usrParams

    $rbLog.WriteLogEntry($usr)
    
    # Throw exception if something went wrong
    if($usr.Status -eq "Failed"){
          Throw $usr.Message
    }
    #endregion

    # Sleep to ensure AD replication has taken place
    Sleep 120

    #region Execute runbook to enable on-premises mailbox
    $mb = .\Enable-UserMailboxOnPremise.ps1 @mbParams

    $rbLog.WriteLogEntry($mb)
    
    # Throw exception if something went wrong
    if($mb.Status -eq "Failed"){
          Throw $mb.Message
    }
    #endregion

    #region Execute runbook to enable on-premises skype for business
    $sb = .\Enable-S4BOnPremise.ps1 @sbParams

    $rbLog.WriteLogEntry($sb)
    
    # no exception just logging or write-warning with continue

    # Throw exception if something went wrong
    if($sb.Status -eq "Failed"){
          Throw $sb.Message
    }
    #endregion
    
    #region Execute runbook to run a Azure AD Syncronization
    $attempt = 1
    $stop = 2

    while($true)
    {
        $aad = .\Invoke-AzureADSync.ps1 -ComputerName DKHQAADS01 -SyncType Delta

        $rbLog.WriteLogEntry($aad)
        $rbLog.WriteLogEntry($aad.RunbookName,"Azure AD Sync Attempts=$($aad.AADSync.Values.Status.Attempts), Success=$($aad.AADSync.Values.Status.Success), Failed=$($aad.AADSync.Values.Status.Failed)")

        if($aad.Status -ne "Success" -and  $attempt -lt $stop){
            Sleep 120
            $attempt++
        }
        else{Break;}
    }
  
    # Throw exception if something went wrong
    if($aad.Status -eq "Failed"){
          Throw $aad.Message
    }
    #endregion
    
    #region Execute runbook to see if the user is syncronized to azure AD
    $attempt = 1
    $stop = 2

    while($true)
    {
        $azu = .\Get-AzureADUser.ps1 $UserPrincipalName

        $rbLog.WriteLogEntry($azu)
        $rbLog.WriteLogEntry($azu.RunbookName,"Azure AD User Object Count is $($azu.ObjectCount)")

        if ($azu.ObjectCount -eq 0 -and $attempt -lt $stop){
            Sleep 30
            $attempt++
        }
        else{Break;}
    }
 
    # Throw exception if something went wrong
    if($azu.Status -eq "Failed"){
        Throw $azu.Message
    }
    #endregion

    #region Execute runbook to assign o365 license
    $lic = .\Set-O365License.ps1 @licParams

    $rbLog.WriteLogEntry($lic)
    
    # Throw exception if something went wrong
    if($lic.Status -eq "Failed"){
          Throw $lic.Message
    }#>
    #endregion

    #region Execute runbook to migrate mailbox to o365
    $mig = .\New-O365MailboxMigration.ps1 -UserprincipalName $UserPrincipalName

    $rbLog.WriteLogEntry($mig)
    
    # Throw exception if something went wrong
    if($mig.Status -eq "Failed"){
          Throw $mig.Message
    }#>
    #endregion

    #region Disable EmailAddressPolicy and set PrimarySMTPAdress to alias

    $module = .\Connect-ExchangeOnline.ps1
    $rbLog.WriteLogEntry($module)

    # Make sure that the modules were imported for the runspace
    if($module.ObjectCount -lt 1){
        Throw "Error - One or more modules was not imported"
    }

    $attempt = 1
    $stop = 10

    while($true)
    {
        $movereq = Get-MoveRequest -Identity "$UserPrincipalName*"

        if($movereq.status -ne "Completed" -and $attempt -lt $stop)
        {   
            $rbLog.WriteLogEntry($RunbookName, "MoveRequest Status for $($movereq.DisplayName) is $($movereq.Status)")
            $rbLog.WriteLogEntry($RunbookName, "Attempt: $attempt, Sleep 60 Seconds")
                     
            Sleep 60
            $attempt++
        }
        else
        {
            Break;
        }
    }

    #$UserPrincipalName = "thstore1008@ecco.com"
    #$alias = "Store-thpopup2@ecco.com"

    Remove-PSSession -name $($module.Connect.Session.Name)
    $rbLog.WriteLogEntry($RunbookName, "Removing session $($module.Connect.Session.Name)")

    if($movereq.status -eq "Completed")
    {
        $rbLog.WriteLogEntry("MoveRequest status for $($movereq.DisplayName) is $($movereq.status)")
              
        # Import Modules and setup implicit remoting, use component runbooks to setup implicit remoting
        $module = .\Connect-ExchangeOnPrem.ps1
        $rbLog.WriteLogEntry($module)

        # Make sure that the modules were imported for the runspace
        if($module.ObjectCount -lt 1){
            Throw "Error - One or more modules was not imported"
        }

        Set-RemoteMailbox -Identity $UserPrincipalName -EmailAddressPolicyEnabled $false
        $rbLog.WriteLogEntry($RunbookName, "Disable EmailAddressPolicy for user $UserPrincipalName")

        Set-RemoteMailbox -Identity $UserPrincipalName -PrimarySmtpAddress $alias
        $rbLog.WriteLogEntry($RunbookName, "Set PrimarySMTPAddress to $alias for user $UserPrincipalName")
   
        Remove-PSSession -name $($module.Connect.Session.Name)
        $rbLog.WriteLogEntry($RunbookName, "Removing session $($module.Connect.Session.Name)")
    }
    else
    {  
        $rbLog.WriteLogEntry("MoveRequest status for $($movereq.DisplayName) is $($movereq.status)")

        Throw "EmailAddressPolicy and PrimarySMTPAddress were not set and needs to be set manually due to move request not beeing completed"
    }
    #endregion

    #region Execute runbook to migrate skype for business

    #$UserPrincipalName = "thstore1009@ecco.com"

    $attempt = 1
    $stop = 30

    while($true)
    {
        $lic = .\Get-O365MappedLicense.ps1 $UserPrincipalName
        
        $rbLog.WriteLogEntry($lic)
            
        $s4bServicePlan = $lic.Map | ?{$_.ServicePlan -eq "Skype for Business Online (Plan 2)"}

        if ($s4bServicePlan.ProvisioningStatus -ne "Success" -and $attempt -lt $stop)
        {
            $rbLog.WriteLogEntry($RunbookName, "Status for ServicePlan $($s4bServicePlan.ServicePlan) is $($s4bServicePlan.ProvisioningStatus)")
            $rbLog.WriteLogEntry($RunbookName, "Attempt: $attempt, Sleep 30 Seconds")

            Sleep 30
            $attempt++
        }
        else
        {
            Break;
        }
    }

    if($s4bServicePlan.ProvisioningStatus -eq "Success")
    {  
        # Check if user has skype onpremise account

        $s4bmig = .\New-S4BUserMigration.ps1 @sbmigparams
        $rbLog.WriteLogEntry($s4bmig)
    }
    else
    {
        $rbLog.WriteLogEntry($s4bmig.RunbookName,"Could not create skype for business move request - $($s4bmig.Message)")
        $rbLog.WriteLogEntry($s4bmig.RunbookName,"Provisioning status for ServicePlan $($s4bServicePlan.ServicePlan) is $($s4bServicePlan.ProvisioningStatus)")
    }
    
    #endregion

    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Workflow Finished Successfully"
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

    # Build and send report via mail    
    $r = [RunbookReport]::new()
    $r.setStyle([Style]::DarkBlue)
    $r.addContent("Trace Log",$rbLog.Log.psobject.BaseObject)
    $report = $r.getReport()

   
    # optional, use Send-Email to send email or sms notifications, for sms use EmailAddressTo file with +45xxxxxxxx@sms.ecco.local
    $email = .\Send-Email.ps1 -EmailAddressTO $(Get-AutomationVariable -Name "Email-PJE") -Subject "Daily Report $RunbookName" -Body $report -AsHtml
    $rbLog.WriteLogEntry($email)

    $props.Add('Trace',$rbLog.Log)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    Write-Output $out
}
