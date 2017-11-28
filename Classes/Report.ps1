Enum Style{

    DarkBlue
}

Class Report{

    $TimeStamp = [DateTime]::Now      
}

Class RunbookReport : Report{

    [Style]$Style
    [Object]$Content   

    # Hidden Properties
    hidden [String]$CSS
    hidden [Object]$Report
    hidden [String]$PostContent

    RunbookReport(){
        
    } 

    [Void] setStyle ([Style]$Style){
        $this.Style = $Style

        switch ($this.Style)
        {
            'DarkBlue' {

                $this.CSS = "<style>"
                $this.CSS += "h1, h5, th {text-align: Left; font-family: Segoe UI; font-size: 10pt;}"
                $this.CSS += "table {margin: auto; font-family: Segoe UI;}"
                $this.CSS += "th { background: #0046c3; color: #fff; max-width: 400px; padding: 5px 10px;}"
                $this.CSS += "td { font-size: 11px; padding: 5px 20px; color: #000;}"
                $this.CSS += "tr { background: #b8d1f3;}"
                $this.CSS += "</style>"
            }
        }
    }

    [Void] addContent ([String]$Header,[Object]$Body){
        
        $this.Content += $Body | ConvertTo-HTML -Fragment -PreContent "<H1>$Header</H1>"
        write-host $this.Content
    }

    [Object] getReport (){
        
        $this.doGenerate()
        return $this.Report
    }

    hidden [Void] doGenerate (){

        $this.PostContent = "<h5>Report generated $($this.TimeStamp)</h5>"
        $this.Report = ConvertTo-Html -Head $this.CSS -PostContent $this.PostContent -body $this.Content
        write-host $this.Report
    }
}

<#
$heading = "Heading before the report"

# Initialize runbook Log
[Array]$instance = [RunbookLog]::New()

# Clone Logging Array to ArrayList to utalize array methods
[System.Collections.ArrayList]$Log = $instance.Clone()

# Clear Cloned array for default entry
$Log.clear()

# Initialize trace output stream, if the runbook is run in Azure the computername will return CLIENT
$Log.Add($Instance.WriteLogEntry($RunbookName,"Running on ($env:COMPUTERNAME)")) | Out-Null

$props = @{'Legs'="2";'Arms'=2}
$body = New-Object -TypeName PSObject -Property $props

$r = [RunbookReport]::new()
$r.setStyle([Style]::DarkBlue)
$r.addContent("Output",$body)
$r.addContent("Log",$Log.psobject.BaseObject)
$r.getReport() | out-file c:\temp\test.html 
invoke-item C:\temp\test.html #>
