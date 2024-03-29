#'------------------------------------------------------------------------------
Param(
   [Parameter(Mandatory = $True, HelpMessage = "The Cluster Hostname, FQDN or IP Address")]
   [ValidateNotNullOrEmpty()]
   [String]$Cluster,
   [Parameter(Mandatory = $True, HelpMessage = "The Credential to authenticate to the Cluster")]
   [ValidateNotNullOrEmpty()]
   [System.Management.Automation.PSCredential]$Credential
)
#'------------------------------------------------------------------------------
#'Initialization Section.
#'------------------------------------------------------------------------------
[String]$scriptPath     = Split-Path($myinvocation.mycommand.path)
[String]$scriptSpec     =  $MyInvocation.MyCommand.Definition
[String]$scriptBaseName = (Get-Item $scriptSpec).BaseName
[String]$fileSpec       = "$scriptPath\zapi.xml"
[String]$moduleName     = "DataONTAP"
#'------------------------------------------------------------------------------
#'Load the PSTK.
#'------------------------------------------------------------------------------
Try{
   [String]$command = "Import-Module -Name $moduleName -ErrorAction Stop"
   Invoke-Expression -Command $command -ErrorAction Stop
   Write-Host "Executed Command`: $command"
}Catch{
   Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
   Write-Warning -Message "Please ensure the PowerShell module ""$moduleName"" is installed"
   Break;
}
#'------------------------------------------------------------------------------
#'Connect to the Cluster.
#'------------------------------------------------------------------------------
Try{
   [String]$command = "Connect-NcController -Name $Cluster -HTTPS -ErrorAction Stop | Out-Null"
   Invoke-Expression -Command $command -ErrorAction Stop
   Write-Host "Executed Command`: $command"
}Catch{
   Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
   Write-Warning -Message "Failed Connecting to cluster ""$Cluster"""
   Break;
}
#'------------------------------------------------------------------------------
#'Ensure the zapi.xml file exists and read the content.
#'------------------------------------------------------------------------------
If(Test-Path -Path $fileSpec){
   Try{
      [String]$command = "Get-Content -Path '$fileSpec' -ErrorAction Stop"
      $xml = Invoke-Expression -Command $command -ErrorAction Stop
      Write-Host "Executed Command`: $command"
   }Catch{
      Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
      Break;
   }
}Else{
   Write-Warning -Message "The file '$fileSpec' does not exist"
   Break;
}
#'------------------------------------------------------------------------------
#'Create an XML object and load the ZAPI XML.
#'------------------------------------------------------------------------------
$request = New-Object "System.Xml.XmlDocument"
$request.LoadXml($xml)
#'------------------------------------------------------------------------------
#'Invoke the XML ZAPI.
#'------------------------------------------------------------------------------
Try{
   $command = "Invoke-NcSystemApi `$request -ErrorAction Stop"
   $response = Invoke-Expression -Command $command -ErrorAction Stop
   Write-Host "Executed Command`: $command"
}Catch{
   Write-Warning -Message $("Failed Executing Command`: $command. Error " + $_.Exception.Message)
   Break;
}
$response.results
