 
<#
.DESCRIPTION
    This runbook controls the flow of Employee Pictures from HR SAP to Office 365

    Steps
    •	Get all new pictures from Zeus fileshare, changed pictures are exported nightly
    •	Resize pictures to fit Sharepoint Online and Exchange Online
    •	Uploads Pictures to SPO and EXO

.INPUTS
    NA

.OUTPUTS
    [Object]

.NOTES
    Version:        1.0.0
    Author:			SKJA
    Creation Date:	2017.03.29
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
$RunbookName = "Start-O365EmployeePictureSync"

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
            Throw "Error - Connecting to Azure failed"
        } 
    }

    Write-verbose "Successfully Logged into Azure!"
            
    # Import Modules and setup implicit remoting, use component runbooks to setup implicit remoting
    $modules = @()
    $modules += .\Connect-ExchangeOnlineRPC.ps1
    $modules += .\Connect-SharepointOnlineCSOM.ps1
    $modules += .\Connect-ExchangeOnline.ps1

    # Add trace output from component runbooks to this tracelog
    $trace += "$($modules[0].Trace)"
    $trace += "$($modules[1].Trace)"
    $trace += "$($modules[2].Trace)"

    # Make sure that the modules were imported for the runspace
    if($modules[0].ObjectCount -lt 1 -or $modules[1].ObjectCount -lt 1 -or $modules[2].ObjectCount -lt 1)
    {
        Throw "Error - One or more modules was not imported"
    }

    <#     Processing begins here....     #>
    # Gather variables and credentials needed
    $HRPPicturesPath = Get-AutomationVariable -Name "HRP-EmpPictures"
    $HRPCredentials = Get-AutomationPSCredential -Name "HRP-EmpPicturesUser"
    $SPOEmployeePhotosDocLibrary = Get-AutomationVariable -Name "SPO-EmployeePhotosDocLibrary"
    $SPOEmployeePhotosDocFolder = Get-AutomationVariable -Name "SPO-EmployeePhotosDocFolder"
    $HRPPSDriveName = "HRPPictures"

    $SPOContext       = $modules[1].SPOMySiteCtx
    $SPOAdminContext  = $modules[1].SPOAdminCtx
    $SPOPeopleManager = $modules[1].SPOPeopleManager

    #Map the drive with employee pictures

    $trace += Add-TraceEntry "Mapping PSDrive for Employee Pictures: $($HRPPicturesPath)"
    New-PSDrive -Name HRPPictures -PSProvider FileSystem -Root $HRPPicturesPath -Credential $HRPCredentials | Out-Null
    
    #Verify we have the folders needed for processing:
    $trace += Add-TraceEntry "Verifying folders needed for processing"
    If(!(test-path "$($HRPPSDriveName):\Resized"))
    { New-Item -ItemType Directory -Force -Path "$($HRPPSDriveName):\Resized" -ErrorAction SilentlyContinue }

    If(!(test-path "$($HRPPSDriveName):\Processed")) 
    { New-Item -ItemType Directory -Force -Path "$($HRPPSDriveName):\Processed" -ErrorAction SilentlyContinue }

    $trace += Add-TraceEntry "Gettings new employee pictures that have not been processed yet"
    $SourcePictures = Get-ChildItem -Path "$($HRPPSDriveName):\" -File

    if ($SourcePictures.count -ne 0) {
        $trace += Add-TraceEntry "Found $($SourcePictures.count) pictures that need processing"
        foreach ($SourcePicture in $SourcePictures) {
            $trace += Add-TraceEntry "*** Processing user: $($SourcePicture.BaseName) ***"
            $statusSPO = "Pending"
            $statusEXO = "Pending"

            #Create new thumbnails with correct file name format and sizes
            $newImageNamePrefix = $SourcePicture.BaseName -replace "@","_" -replace '\.',"_"
            
            $trace += Add-TraceEntry "Compressing pictures"
            $sthump = .\Compress-Picture.ps1 -SourceImagePath "$($SourcePicture.FullName)" -Width 48 -TargetImagePath ("$((Get-PSDrive $HRPPSDriveName).Root)\Resized\" + $newImageNamePrefix + "_SThumb.jpg") -CompressionQuality 75 -WarnIfNotSquare
            $mthump = .\Compress-Picture.ps1 -SourceImagePath "$($SourcePicture.FullName)" -Width 72 -TargetImagePath ("$((Get-PSDrive $HRPPSDriveName).Root)\Resized\" + $newImageNamePrefix + "_MThumb.jpg") -CompressionQuality 75 
            $lthump = .\Compress-Picture.ps1 -SourceImagePath "$($SourcePicture.FullName)" -Width 300 -TargetImagePath ("$((Get-PSDrive $HRPPSDriveName).Root)\Resized\" + $newImageNamePrefix + "_LThumb.jpg") -CompressionQuality 85 
            $exothump = .\Compress-Picture.ps1 -SourceImagePath "$($SourcePicture.FullName)" -Width 240 -TargetImagePath ("$((Get-PSDrive $HRPPSDriveName).Root)\Resized\" + $newImageNamePrefix + "_EXOThumb.jpg") -CompressionQuality 75 
            
            if ($sthump.Status -ne "Success" -OR $mthump.Status -ne "Success" -OR $lthump.Status -ne "Success" -OR $exothump.Status -ne "Success") {
                $trace += Add-TraceEntry "Error found during picture compression, log below:"
                $trace += $sthump.Trace
                $trace += $mthump.Trace
                $trace += $lthump.Trace
                $trace += $exothump.Trace
            }

            #Upload Sharepoint Online pictures.
            
            $resSPstmb = .\Write-SPOFile.ps1 -SPOClientContext $SPOContext -FilePath $($sthump.TargetImagePath) -DocumentLibrary $SPOEmployeePhotosDocLibrary -FolderName $SPOEmployeePhotosDocFolder
            $trace += $resSPstmb.Trace

            $resSPmtmb = .\Write-SPOFile.ps1 -SPOClientContext $SPOContext -FilePath $($mthump.TargetImagePath) -DocumentLibrary $SPOEmployeePhotosDocLibrary -FolderName $SPOEmployeePhotosDocFolder
            $trace += $resSPmtmb.Trace

            $resSPltmb = .\Write-SPOFile.ps1 -SPOClientContext $SPOContext -FilePath $($lthump.TargetImagePath) -DocumentLibrary $SPOEmployeePhotosDocLibrary -FolderName $SPOEmployeePhotosDocFolder
            $trace += $resSPltmb.Trace

            #Update Sharepoint user information if pictures was uploaded successfully
            if ($resSPstmb.Status -eq "Success" -AND $resSPmtmb.Status -eq "Success" -AND $resSPltmb.Status -eq "Success") {
                #All Pictures uploaded successfully, goahead and update profile with new photo URL.
                $resSPUserInfo = .\Set-SPOUserProfilePhotoInfo.ps1 -SPOAdminContext $SPOAdminContext -SPOPeopleManager $SPOPeopleManager -UserPrincipalName $($SourcePicture.BaseName) -PictureURL $resSPmtmb.FileURL -ExchangeSyncState 0 -PicturePlaceHolder 0
                $trace += $resSPUserInfo.Trace
                if ($resSPUserInfo.Status -eq "Success") { $statusSPO = "Success" }
                else { $statusSPO = "Failed" }

            }
            else {
                $trace += Add-TraceEntry "Error processing user completely in SPO, keeping user photo in processing queue for next run."
                $statusSPO = "Failed"
                continue
            }

            #Upload Exchange Online Picture
            $resEXOpic = .\Set-EXOUserPhoto.ps1 -FilePath $($exothump.TargetImagePath) -UserPrincipalName $($SourcePicture.BaseName) -EXOModule $($modules[2].Connect.Module.Name)
            #$trace += $resEXOpic.Trace
            if ($resEXOpic.Status -eq "Success") {
                $statusEXO = "Success"
                $trace += $resEXOpic.Trace
            } 
            else {
                #Retry without the RPS proxy, and see if it works.
                $trace += Add-TraceEntry "Exchange Online photo upload failed without RPC proxy, trying with."
                $resEXOpic = .\Set-EXOUserPhoto.ps1 -FilePath $($exothump.TargetImagePath) -UserPrincipalName $($SourcePicture.BaseName) -EXOModule $($modules[0].Connect.Module.Name)
                if ($resEXOpic.Status -eq "Success") {
                    $statusEXO = "Success"
                    $trace += $resEXOpic.Trace
                }
                else { 
                    $trace += Add-TraceEntry "Exchange Online photo upload failed with RPC proxy also."
                    $statusEXO = "Failed"
                }
            }

            if ($statusEXO -eq "Success" -AND $statusSPO -eq "Success") {
                #Both SPO and EXO was handled successfully, move the original picture into the processed folder.
                $trace += Add-TraceEntry "User was processed successfully, moving picture out of processing queue and into the processed folder."
                Move-Item -Path $SourcePicture.FullName -Destination "$((Get-PSDrive $HRPPSDriveName).Root)\Processed\" -Force
            }
            else { 
                $trace += Add-TraceEntry "User was not processed successfully, keeping picture for reprocessing." 
                $trace += Add-TraceEntry " : SharePoint status $($statusSPO) - Exchange Online Status: $($statusEXO)"
                }

        }
    }
    else { $trace += Add-TraceEntry "No pictures found that need processing" }

    <#     Processing ends here....       #>   
    # Return values used for further processing, add properties if needed
    $props = [Ordered]@{'Status' = "Success"
                        'Message' = "Workflow Finished Successfully"
                        'ObjectCount' = 1}
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
                        'Message' = "Error Message"
                        'ObjectCount' = 0}
    
    Write-Error $status
}
finally
{
    # Remove session if needed, change if needed
    Remove-PSSession -name $($modules[0].Connect.Session.Name) -ErrorAction Ignore
    $trace += Add-TraceEntry "Removing session $($modules[0].Connect.Session.Name)"

        Remove-PSSession -name $($modules[2].Connect.Session.Name) -ErrorAction Ignore
    $trace += Add-TraceEntry "Removing session $($modules[2].Connect.Session.Name)"

    Remove-PSDrive -Name $HRPPSDriveName -ErrorAction SilentlyContinue
    $trace += Add-TraceEntry "Removing PDSrive $($HRPPSDriveName)"

    $props.Add('Trace',$trace)
    $props.Add('RunbookName',$RunbookName)

    $out = New-Object -TypeName PSObject -Property $props

    .\Send-Email.ps1 -EmailAddressTO "eap-it-operation@ecco.com" -Subject "Office 365 Picture Sync has finished" -Body $out

    Write-Output $out
}   
