Param(
   [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
   [String]$Cluster
)
#'------------------------------------------------------------------------------
Function Get-IsoDateTime{
   Return (Get-IsoDate) + " " + (Get-IsoTime)
}#'End Function Get-IsoDateTime.
#'------------------------------------------------------------------------------
Function Get-IsoDate{
   Return Get-Date -uformat "%Y-%m-%d"
}#'End Function Get-IsoDate.
#'------------------------------------------------------------------------------
Function Get-IsoTime{
   #Return Get-Date -uformat "%H:%M:%S"
   Return Get-Date -Format HH:mm:ss.fff
}#'End Function Get-IsoTime.
#'------------------------------------------------------------------------------
Function Write-Log{
   Param(
      [Switch]$Info,
      [Switch]$Error,
      [Switch]$Debug,
      [Switch]$Warning,
      [String]$Message
   )
   #'---------------------------------------------------------------------------
   #'Set the default log type if not provided.
   #'---------------------------------------------------------------------------
   If((-Not($Info)) -And (-Not($Debug)) -And (-Not($Warning)) -And (-Not($Error))){
      [String]$line = $("`[" + (Get-IsoDateTime) + "`],`[INFO`]," + $Message)
   }
   #'---------------------------------------------------------------------------
   #'Add an entry to the log file and disply the output. Format: [Date],[TYPE],MESSAGE
   #'---------------------------------------------------------------------------
   [String]$lineNumber = $MyInvocation.ScriptLineNumber
   Try{
      If($Error){
         If([String]::IsNullOrEmpty($_.Exception.Message)){
            [String]$line = $("`[" + (Get-IsoDateTime) + "`],`[ERROR`],`[LINE $lineNumber`]," + $Message)
         }Else{
            [String]$line = $("`[" + (Get-IsoDateTime) + "`],`[ERROR`],`[LINE $lineNumber`]," + $Message + ". Error " + $_.Exception.Message)
         }
      }ElseIf($Info){
         [String]$line = $("`[" + (Get-IsoDateTime) + "`],`[INFO`]," + $Message)
      }ElseIf($Debug){
         [String]$line = $("`[" + $(Get-IsoDateTime) + "`],`[DEBUG`],`[LINE $lineNumber`]," + $Message)
      }ElseIf($Warning){
         [String]$line = $("`[" + (Get-IsoDateTime) + "`],`[WARNING`],`[LINE $lineNumber`]," + $Message)
      }
      #'-----------------------------------------------------------------------
      #'Display the console output.
      #'-----------------------------------------------------------------------
      If($Error){
         If(-Not([String]::IsNullOrEmpty($_.Exception.Message))){
            Write-Host $($line + ". Error " + $_.Exception.Message) -Foregroundcolor Red
         }Else{
            Write-Host $line -Foregroundcolor Red
         }
      }ElseIf($Warning){
         Write-Host $line -Foregroundcolor Yellow
      }ElseIf($Debug){
         Write-Host $line -Foregroundcolor Magenta
      }Else{
         Write-Host $line -Foregroundcolor White
      }
      Add-Content -Path "$scriptLogPath.log" -Value $line -ErrorAction Stop
      If($Error){
         Add-Content -Path "$scriptLogPath.err" -Value $line -ErrorAction Stop
      }
   }Catch{
      Write-Warning "Could not write entry to output log file ""$scriptLogPath.log"". Log Entry ""$Message"""
   }
}#'End Function Write-Log.
#'------------------------------------------------------------------------------
Function Connect-OntapCluster{
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The destination cluster name or IP Address")]
      [String]$Cluster,
      [Parameter(Mandatory = $True, HelpMessage = "The Credentials to authenticate to the Cluster")]
      [System.Management.Automation.PSCredential]$Credential
   )
   #'---------------------------------------------------------------------------
   #'Connect to the cluster if required.
   #'---------------------------------------------------------------------------
   If([String]::IsNullOrEmpty($global:CurrentNcController.Name)){
      [String]$command = "Connect-NcController -Name $Cluster -HTTPS -Credential `$Credential -ErrorAction Stop"
      Try{
         Invoke-Expression -Command $command -ErrorAction Stop | Out-Null
         Write-Log -Info -Message "Executed Command`: $command"
         Write-Log -Info -Message $("Connect to cluster ""$Cluster"" as user """ + $Credential.Username + """")
      }Catch{
         Write-Log -Error -Message "Failed Executing Command`: $command"
         Return $False;
      }
   }
   Return $True;
}#'End Function Connect-OntapCluster.
#'------------------------------------------------------------------------------
Function Get-OntapCredential{
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
      [String]$Cluster
   )
   $credential = Get-CachedCredential -Cluster $Cluster
   If(-Not($credential)){
      Do{
         $credential = Get-ClusterCredential -Cluster $Cluster
      }Until($True)
   }
   Return $credential;
}
#'End Function Get-OntapCredential.
#'------------------------------------------------------------------------------
Function Get-CachedCredential{
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
      [String]$Cluster
   )
   #'---------------------------------------------------------------------------
   #'Enumerate cached credential.
   #'---------------------------------------------------------------------------
   $credential = $Null
   $cache      = Get-NcCredential -Name $Cluster
   If($Null -ne $cache){
      $credential = $cache.Credential
   }
   Return $credential;
}
#'End Function Get-CachedCredential.
#'------------------------------------------------------------------------------
Function Get-ClusterCredential{
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory=$True, HelpMessage="The cluster name or IP Address")]
      [String]$Cluster,
      [Parameter(Mandatory=$False, HelpMessage="The Maximum number of attempts to prompt for credentials")]
      [Int]$MaxAttempts=5
   )
   #'---------------------------------------------------------------------------
   #'Enumerate the current user's domain and also format the user name to be used for the credential prompt.
   #'---------------------------------------------------------------------------
   [String]$domainName       = $env:USERDOMAIN
   [String]$userName         = "$DomainName\$env:USERNAME"
   [Int]$attempts            = 1
   [Int]$errorCount          = 0
   [String]$credentialPrompt = "Enter your credentials (attempt $attempts out of $MaxAttempts):"
   #'---------------------------------------------------------------------------
   # Loop through prompting for and validating credentials, until the credentials are confirmed, or the maximum number of attempts is reached.
   #'---------------------------------------------------------------------------
   Do{
      $valid        = $False
      $errorMessage = $Null
      $response     = $Null
      $credential   = $host.ui.promptForCredential("Connect to cluster $Cluster", $credentialPrompt, $userName, "")
      #'------------------------------------------------------------------------
      #'Verify the credentials prompt wasn't bypassed.
      #'------------------------------------------------------------------------
      If($credential){
         #'---------------------------------------------------------------------
         #'If the user name was changed, then switch to using it for this and future credential prompt validations.
         #'---------------------------------------------------------------------
         If($credential.UserName -ne $userName) {
            $userName = $credential.UserName
         }
         #'---------------------------------------------------------------------
         #'Check authentication for the domain account by invoking an LDAP bind.
         #'---------------------------------------------------------------------
         If((-Not([String]::IsNullOrEmpty($credential.GetNetworkCredential().Domain))) -Or ($userName.Contains("@"))){
            Try{
               $root   = "LDAP://" + ([ADSI]'').distinguishedName
               $domain = New-Object System.DirectoryServices.DirectoryEntry($root, $credential.Username, $credential.GetNetworkCredential().Password)
            }Catch{
               If($_.Exception.InnerException -like "*The server could not be contacted*"){
                  $errorMessage = "Could not contact a server for the specified domain on attempt $attempts out of $MaxAttempts."
               }Else{
                  $errorMessage = $("Unexpect Error: """ + $($_.Exception.Message) + """ on attempt $attempts out of $MaxAttempts.")
               }
               $errorCount++
            }
            #'------------------------------------------------------------------
            #'If there wasn't a failure authenticating to the domain test the validation of the credentials, and if it fails record a failure message.
            #'------------------------------------------------------------------
            If(-Not($errorMessage)){
               If($Null -ne $domain.Name){
                  $valid = $True
               }
               If(-Not($valid)){
                  $errorMessage = "Bad user name or password used on credential prompt attempt $attempts out of $MaxAttempts."
                  $errorCount++
               }
            }
         }Else{
            #'------------------------------------------------------------------
            #'Check authentication for the local account by enumerating the ONTAP version.
            #'------------------------------------------------------------------
            Try{
               $response = Get-NcOntapVersion -Cluster $Cluster -Credential $credential -ErrorAction Stop
            }Catch{
               $errorMessage = $("Unexpect Error: """ + $($_.Exception.Message) + """ on attempt $attempts out of $MaxAttempts.")
               $errorCount++
            }
            #'------------------------------------------------------------------
            #'Check authentication for the local account using the PSTK.
            #'------------------------------------------------------------------
            If($Null -eq $response){
               $valid = Connect-OntapCluster -Cluster $Cluster -Credential $credential
               If($valid){
                  $response     = $True
                  $errorMessage = $Null
               }Else{
                  $errorMessage = $("Failed connecting to cluster ""$Cluster"" as user """ + $credential.UserName + """")
                  $errorCount++
               }
            }
            #'------------------------------------------------------------------
            #'If there wasn't a failure talking to the domain test the validation of the credentials, and if it fails record a failure message.
            #'------------------------------------------------------------------
            If(-Not($errorMessage)){
               If($Null -ne $response){
                  $valid = $True
               }
               If(-Not($valid)){
                  $errorMessage = "Bad user name or password used on credential prompt attempt $attempts out of $MaxAttempts."
                  $errorCount++
               }
            }
         }
         #'---------------------------------------------------------------------
         #'Otherwise the credential prompt was (most likely accidentally) bypassed so record a failure message.
         #'---------------------------------------------------------------------
      }Else{
         $errorMessage = "Credential prompt was closed or skipped on attempt $attempts out of $MaxAttempts."
      }
      #'------------------------------------------------------------------------
      #'If there was a failure message recorded above, display it, and update credential prompt message.
      #'------------------------------------------------------------------------
      If($errorMessage){
         Write-Log -Error "$errorMessage"
         $attempts++
         If($Attempt -lt $MaxAttempts){
            $credentialPrompt = "Authentication Error. Please try again (attempt $attempts out of $MaxAttempts):"
         }ElseIf($Attempt -eq $MaxAttempts) {
            $credentialPrompt = "Authentication Error. This is your final chance (attempt $attempts out of $MaxAttempts):"
         }
      }
   }Until(($valid) -Or ($attempts -gt $MaxAttempts))
   If(-Not($valid)){
      Return $Null;
   }
   Return $credential;
}
#'End Function Get-ClusterCredential.
#'------------------------------------------------------------------------------
Function Get-NcAuthorization{
   [Alias("Get-NcAuth")]
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory = $True, HelpMessage = "The Credential to authenticate to AIQUM")]
      [ValidateNotNullOrEmpty()]
      [System.Management.Automation.PSCredential]$Credential
   )
   #'---------------------------------------------------------------------------
   #'Set the authentication header to connect to ONTAP.
   #'---------------------------------------------------------------------------
   $auth    = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credential.UserName + ':' + $Credential.GetNetworkCredential().Password))
   $headers = @{
      "Authorization" = "Basic $auth"
      "Accept"        = "application/json"
      "Content-Type"  = "application/json"
   }
   Return $headers;
}#'End Function Get-NcAuthorization.
#'------------------------------------------------------------------------------
Function Get-NcOntapVersion{
   [CmdletBinding()]
   Param(
      [Parameter(Mandatory = $True, HelpMessage = "The Cluster Hostname, FQDN or IP Address")]
      [ValidateNotNullOrEmpty()]
      [String]$Cluster,
      [Parameter(Mandatory = $True, HelpMessage = "The Credential to authenticate to AIQUM")]
      [ValidateNotNullOrEmpty()]
      [System.Management.Automation.PSCredential]$Credential
   )
   #'---------------------------------------------------------------------------
   #'Set the authentication header to connect to AIQUM.
   #'---------------------------------------------------------------------------
   $headers = Get-NcAuthorization -Credential $Credential
   #'---------------------------------------------------------------------------
   #'Enumerate the ONTAP version.
   #'---------------------------------------------------------------------------
   [String]$uri = "https://$Cluster/api/cluster"
   Try{
      $response = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -ErrorAction Stop
      Write-Log -Info -Message "Enumerated ONTAP version on cluster ""$Cluster"" using URI ""$uri"""
   }Catch{
      Write-Log -Error -Message $("Failed enumerating ONTAP version on cluster ""$Cluster"" using URI ""$uri"". Error " + $_.Exception.Message + ". Status Code " + $_.Exception.Response.StatusCode.value__)
   }
   If($Null -ne $response){
      Return $response.version;
   }Else{
      Return $Null;
   }
}#'End Function Get-NcOntapVersion.
#'------------------------------------------------------------------------------
#'Set the certificate policy and TLS version.
#'------------------------------------------------------------------------------
Add-Type @"
   using System.Net;
   using System.Security.Cryptography.X509Certificates;
   public class TrustAllCertsPolicy : ICertificatePolicy{
   public bool CheckValidationResult(
   ServicePoint srvPoint, X509Certificate certificate,
   WebRequest request, int certificateProblem){
      return true;
   }
}
"@
[System.Net.ServicePointManager]::SecurityProtocol  = [System.Net.SecurityProtocolType]'Tls12'
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
#'------------------------------------------------------------------------------
#'Initialization Section. Define Global Variables.
#'------------------------------------------------------------------------------
[String]$scriptPath     = Split-Path($MyInvocation.MyCommand.Path)
[String]$scriptSpec     = $MyInvocation.MyCommand.Definition
[String]$scriptBaseName = (Get-Item $scriptSpec).BaseName
[String]$scriptName     = (Get-Item $scriptSpec).Name
[String]$scriptLogPath  = $("$scriptPath\Logs\" + $(Get-IsoDate))
[String]$parentPath     = $scriptPath.SubString(0, $scriptPath.lastIndexOf("\"))
#'------------------------------------------------------------------------------
#'Ensure the logs folder exists within the scripts working directory
#'------------------------------------------------------------------------------
If(-Not(Test-Path -Path "$scriptPath\Logs")){
   Try{
      New-Item -Type directory -Path "$scriptPath\Logs" -ErrorAction Stop | Out-Null
   }Catch{
      Write-Warning -Message "Failed creating folder ""$scriptPath\logs"""
      Break;
   }
}
#'------------------------------------------------------------------------------
#'Import the PSTK.
#'------------------------------------------------------------------------------
[String]$moduleName = "NetApp.ONTAP"
[String]$command    = "Import-Module '$moduleName' -ErrorAction Stop"
Try{
   Invoke-Expression -Command $command -ErrorAction Stop
   Write-Log -Info -Message "Executed Command`: $command"   
}Catch{
   Write-Log -Error -Message "Failed Executing Command`: $command"
   Throw "Failed Importing Module ""$moduleName"""
}
#'------------------------------------------------------------------------------
#'Enumerate and validate credential authentication to the cluster.
#'------------------------------------------------------------------------------
$credential = Get-OntapCredential -Cluster $Cluster
#'------------------------------------------------------------------------------
#'Enumerate the ONTAP version.
#'------------------------------------------------------------------------------
Try{
   $response = Get-NcOntapVersion -Cluster $Cluster -Credential $Credential -ErrorAction Stop
}Catch{
   Write-Log -Error -Message "Failed enumerating ONTAP version for cluster ""$Cluster"""
   Break;
}
#'------------------------------------------------------------------------------
#'Write the ONTAP version to the log file.
#'------------------------------------------------------------------------------
If($Null -ne $response){
   [String]$version = $($response.generation.ToString() + "." + $response.major.ToString())
   If($Null -ne $response.minor){
      [String]$version += $("." + $response.minor.ToString())
   }
   Write-Log -Info -Message "Cluster ""$Cluster"" is running ONTAP version ""$version"""
}Else{
   Try{
      [String]$version = (Get-NcSystemVersion).Value.Split(":")[0].Split(" ")[2]
   }Catch{
      Write-Log -Error -Message "Failed Enumerating ONTAP version for cluster ""$Cluster"""
      Break;
   }
   Write-Log -Info -Message "Cluster ""$Cluster"" is running ONTAP version ""$version"""
}
#'------------------------------------------------------------------------------