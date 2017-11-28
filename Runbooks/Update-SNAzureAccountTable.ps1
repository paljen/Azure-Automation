  
 <#
.DESCRIPTION
    Updates the u_azure_automation_account table in ServiceNow with azure automation account information

    Runbook Tagging
    •	Modular, reusable – single purpose runbooks. - Tag: Component
    •	Modular, reusable – single purpose runbooks used in Components - Tag: Core
    •	Non modular, made for a specific purpose - Tag: Script   
    •	Flow specific runbooks - Tag: Controller
    •	Integration runbooks combined with webhooks - Tag: Interface

.OUTPUTS
    [Object]

.NOTES
    Version  : 1.0
    Template : Component
    tVersion : 2.2
    Author   : Palle Jensen (PJE)		
    Note     : {[Major.Minor]} - {Date MM-dd-yyyy}, {Username}, {Description}
    Note     : 1.0 - 21-09-2017, Palle Jensen (PJE), Initial runbook development
#>

[CmdletBinding()]

Param(

)

$ErrorActionPreference = "Stop"

<# To enable verbose stream set `$VerbosePreference to Continue, Verbose should also be 
   switched "On" on the runbook in Azure portal.#>
$VerbosePreference = "Continue"

# Provide the runbook with the same name as in Azure, this variable is used mainly for tracking
$RunbookName = "Update-SNAzureAccountTable"

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
        Get-AzureRmAutomationAccount -Verbose:$false | Out-Null
    }
    catch{
        $conn = .\Connect-AzureRMAutomation.ps1 -Verbose:$false
        
        $rbLog.WriteLogEntry($conn)

        if($conn.status -ne "Success"){
            Throw "Connecting to Azure failed"
        } 
    }
           
    # Query all records from service now table
    $snQuery = .\Get-ServiceNowItemByQuery.ps1 -Table "u_azure_automation_account" -Verbose:$false

    $rbLog.WriteLogEntry($snQuery)

    if($snQuery.ObjectCount -lt 1){
        Throw "Error - Quering data from ServiceNow table: $($params.table)"
    }
    
    $rbLog.WriteLogEntry($RunbookName, "Returned $(($snQuery).Item.count) accounts from table: $($params.table) in ServiceNow")

    [System.Collections.ArrayList]$snItem = @()
    [System.Collections.ArrayList]$snItem += $snQuery.Item

    if(!$snItem){
        $snItem.Add(@{'u_automation_account_name'="Blank"})
        $rbLog.WriteLogEntry($RunbookName, "Creating temporary comparable row")
    }

    [System.Collections.ArrayList]$azAccount = @()

    $acc = Get-AzureRMAutomationAccount -Verbose:$false

    for ($i = 0; $i -lt $acc.count; $i++){ 
        $azAccount.Add($acc[$i]) | Out-Null  
    }
    
    $rbLog.WriteLogEntry($RunbookName, "Returned $($acc.count) accounts from subscription $($conn.AutomationAccount.SubscriptionId)")

    [System.Collections.ArrayList]$compare = @()
    [System.Collections.ArrayList]$compare += (Compare-Object -ReferenceObject $azAccount.AutomationAccountName -DifferenceObject $snItem.u_automation_account_name -IncludeEqual)

    if($compare.count -ne 0)
    {
        # Creates content body used in the rest call
        Function CreateContentBody ($index)
        {
            $content = @{}
            $content.u_subscription_id = $azAccount.item($index).SubscriptionId
            $content.u_resource_group_name = $azAccount.item($index).ResourceGroupName
            $content.u_creation_time = $azAccount.item($index).CreationTime.DateTime.GetDateTimeFormats()[21]
            $content.u_last_modified_time = $azAccount.item($index).LastModifiedTime.DateTime.GetDateTimeFormats()[21]
            $content.u_last_modified_by = $azAccount.item($index).LastModifiedBy
            $content.u_plan = $azAccount.item($index).Plan
            $content.u_state = $azAccount.item($index).State
            $content.u_tags = $azAccount.item($index).Tags
            $content.u_location = $azAccount.item($index).Location
            $content.u_automation_account_name = $azAccount.item($index).AutomationAccountName
            $content
        }#>

        # Enumerator for the entire ArrayList.
        $enum = $compare.GetEnumerator()

        # Create a shallow copy of the ArrayList.
        $compareClone = $compare.Clone()

        $index = 0

        While ($compareClone.Count -ne 0)
        {
            ## Reset pointer
            $enum.Reset()

            # MoveNext, returns true if arraylist has more elements
            While($enum.MoveNext())
            {
                $rbLog.WriteLogEntry($RunbookName, "Processing account $($enum.current.InputObject)")

                # Sort out each object record
                $account_current = $azAccount | ? {$_.AutomationAccountName -eq $enum.current.InputObject}
                $sn_current = $snItem | ? {$_.u_automation_account_name -eq $enum.current.InputObject}

                # If existing runbook object, return index in array. The index is used to create the content body
                $index = 0..($azAccount.count - 1) | Where { $azAccount.AutomationAccountName[$_] -eq $enum.Current.InputObject }

                # Process object record, when the object is only present in SNow for the given automation account
                if($enum.current.sideindicator -match "=>" -and $enum.Current.InputObject -ne "Blank"){
                    $removeItem = .\Remove-ServiceNowItem.ps1 -SysId $($sn_current.sys_id) -Table $($params.Table) -Verbose:$false

                    $rbLog.WriteLogEntry($removeItem)
                }

                # Process object record, when the object is only present in Azure Automation
                if($enum.current.sideindicator -match "<=" -and $enum.Current.InputObject -ne "Blank"){
                    # build content body for rest call

                    $content = CreateContentBody $index

                    $createItem = .\New-ServiceNowItem.ps1 -Content $content -Table $params.Table -Verbose:$false

                    $rbLog.WriteLogEntry($createItem)
                }

                # Process object record, when the object is SNow and the Object has been modified in Azure Automation
                if($enum.current.sideindicator -match "=="){
                    # build content body for rest call
                    $content = CreateContentBody $index

                    $setItem = .\Set-ServiceNowItem.ps1 -Table $($params.Table) -Content $content -SysId $($sn_current.sys_id) -Method Put -Verbose:$false

                    $rbLog.WriteLogEntry($setItem)
                }           

                $compareClone.Remove($($enum.Current)) 
            }        
        }
    }
    else
    {
        $rbLog.WriteLogEntry($RunbookName, "No Subscriptions to process")
    }
       
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
