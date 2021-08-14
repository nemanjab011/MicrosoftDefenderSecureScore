
$AppId = "enter your application id"
$TenantId = "enter your tenant id"
$AppSecret = 'enter your app secret'

#########################################################################################################
# Construct URI and body needed for authentication
$uri = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
$body = @{
    client_id     = $AppId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $AppSecret
    grant_type    = "client_credentials" }



# Get token
$tokenRequest = Invoke-WebRequest -Method Post -Uri $uri -ContentType "application/x-www-form-urlencoded" -Body $body -UseBasicParsing

# Unpack Token
$token = ($tokenRequest.Content | ConvertFrom-Json).access_token

# Base URL
$headers = @{Authorization = "Bearer $token"}

#################################################################################################### 

function Get-Win10IntuneManagedDevice {

    [cmdletbinding()]
    
    param
    (
    [parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$deviceName
    )
    
    try{
    
    if($deviceName){
    
    $DeviceURI = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?filter=deviceName eq '$devicename'"
    (Invoke-RestMethod -Uri $deviceURI -Headers $Headers -Method Get).value

    }
    
    else {
        Write-Host "User has no Intune registered devices"
    }
    
    }catch {
        $ex = $_.Exception
        $errorResponse = $ex.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd();
        Write-Host "Response content:`n$responseBody" -f Red
        Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
        throw "Get-IntuneManagedDevices error"
    }
    

}


##############################################################################################################

############################################################################################################# 


function Get-IntuneDevicePrimaryUser {

    
    [cmdletbinding()]
    
    param
    (
        [Parameter(Mandatory=$true)]
        [string] $deviceId
    )
        
        
        $Resource = "deviceManagement/managedDevices"
        $uri = "https://graph.microsoft.com/beta/$($Resource)" + "/" + $deviceId + "/users"
    
        try {
            
            $primaryUser = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    
            return $primaryUser.value."id"
            
        } catch {
            $ex = $_.Exception
            $errorResponse = $ex.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorResponse)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd();
            Write-Host "Response content:`n$responseBody" -f Red
            Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
            throw "Get-IntuneDevicePrimaryUser error"
        }
    }

############################################################################################################## 
$ATPresourceAppIdUri = 'https://api.securitycenter.microsoft.com'
$ATPoAuthUri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
$ATPbody = [Ordered] @{
    resource = "$ATPresourceAppIdUri"
    client_id = "$appId"
    client_secret = "$appSecret"
    grant_type = 'client_credentials'
}
$ATPresponse = Invoke-RestMethod -Method Post -Uri $ATPoAuthUri -Body $ATPbody -ErrorAction Stop
$ATPaadToken = $ATPresponse.access_token


##############################################################################################################

function Get-ATPAdvancedHuntingQuery {

    
    [cmdletbinding()]
    
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$TxtFilePath
    )

$ATPquery = [IO.File]::ReadAllText(".\atp\$txtfilepath"); # Paste your own query here if not complex
#$ATPquery = [IO.File]::ReadAllText("C:\Users\ybn\OneDrive\temp>\Fix unquoted service path for Windows services.txt"); # Paste your own query here if not complex
$ATPurl = "https://api.securitycenter.microsoft.com/api/advancedqueries/run"
$ATPheaders = @{ 
    'Content-Type' = 'application/json'
    Accept = 'application/json'
    Authorization = "Bearer $ATPaadToken" 
        }    
try {
    
$ATPbody = ConvertTo-Json -InputObject @{ 'Query' = $ATPquery }
$ATPwebResponse = Invoke-WebRequest -Method Post -Uri $ATPurl -Headers $ATPheaders -Body $ATPbody -ErrorAction Stop
$ATPresponse =  $ATPwebResponse | ConvertFrom-Json
$ATPresults = $ATPresponse.Results
$ATPschema = $ATPresponse.Schema

return $ATPresults

} catch {

    $ex = $_.Exception
    $errorResponse = $ex.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($errorResponse)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    Write-Host "Response content:`n$responseBody" -f Red
    Write-Error "Request to $Uri failed with HTTP Status $($ex.Response.StatusCode) $($ex.Response.StatusDescription)"
    throw "Get-ATPAdvancedHuntingQuery error"

    }

}

#################################################################################################### 




$Devicelist = Get-ATPAdvancedHuntingQuery -TxtFilePath '.\Fix unquoted service path for Windows services.txt' | Select-Object ConfigurationName, Devicename, ConfiguratioDescription -Last 20



$RecommendationGroupName = $Devicelist.ConfigurationName[1]


$deviceid_array = @()

foreach($device in $Devicelist) {

    $count = $device.Devicename | Measure-Object -Character


    if ($count.Characters -le 2) {

Write-Host "Getting DdeviceId for $($device.devicename) is not possible beacuse device name has less that 3 letter" -ForegroundColor Red

  } 
  
  else {
    
    $deviceId = Get-Win10IntuneManagedDevice -deviceName $($device.deviceName).split('.')[0]

    foreach ($line in $deviceId) {

        $deviceid_array += New-Object pscustomobject -Property @{
    
            AzureADDeviceId = $($line.id)
            DeviceName = $($line.devicename)
            PrimaryUser = Get-IntuneDevicePrimaryUser -deviceId $line.Id
            UserPrincipalName = $(Get-AzureADUser -ObjectId  $(Get-IntuneDevicePrimaryUser -deviceId $line.Id)).UserPrincipalName
            DeviceId = $(Get-Win10IntuneManagedDevice -deviceName "$device.deviceName" | Select-Object id)
                }   
            }   
       }
Write-Host "Getting DeviceId for $($Device.deviceName)" -ForegroundColor Yellow

     }

Write-Host ""
Write-Host "-------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host ""
Write-host "Primary user of the each device are shown bellow"
Write-Host ""
Write-host "$($deviceid_array | Format-Table | Out-String)" -ForegroundColor Cyan

#$GroupName= $(Write-Host "Creating Azure Active Directory Group " -NoNewline) + $(write-host "P3-IT-$RecommendationGroupName): " -ForegroundColor DarkYellow -NoNewline; Read-Host "P3-IT-$($Devicelist.ConfigurationName)")
$GroupName = "P3-IT-$($RecommendationGroupName)"
#$GroupDescription = $(write-host "Please enter description for this group:  " -ForegroundColor Yellow -NoNewline; Read-Host)
$GroupDescription = "$RecommendationGroupName"
$GroupObjectId = $(New-AzureADGroup -DisplayName $GroupName -mailenabled $false -SecurityEnabled $true -description $GroupDescription -MailNickName "NotSet") | Select-Object ObjectId 

Write-Host "Creating Azure Active Directory Security Group with the name $groupname and following  description $GroupDescription." -ForegroundColor Yellow
Write-Host
Start-Sleep -seconds 2
Write-Host "Please wait"
Write-Host
Start-Sleep -Seconds 2
Write-Host "Please wait"
Start-Sleep -Seconds 2


Write-Host
Write-Host "Getting ObjectId for the Azure Active Directory Group $GroupName" -ForegroundColor Yellow
Write-Host
Start-Sleep -Seconds 2
Write-Host "Please wait"
Write-Host
Start-Sleep -Seconds 2
Write-Host "Please wait"
Write-Host
Write-Host "Group ObjectId is: $($GroupObjectId.objectID)" -ForegroundColor Yellow
Write-Host

foreach($user in $deviceid_array){

    $userId = $user.PrimaryUser
    $upn = $user.userPrincipalName
    $MemebersGroupId = $(Get-azureadGroup -filter "DisplayName eq 'P3-IT-$($RecommendationGroupName)'").ObjectId
    #$mebership = Get-AzureADUserMembership -objectId "$membersgroupid"       
  
                Write-Color -Text "Adding ","$UPN"," to ","$groupname"," Azure Active Directry Group" -Color Yellow,Green,Yellow,Green,Yellow
    
                Add-AzureADGroupMember -objectId $GroupObjectId.objectID -RefObjectId $userId -ErrorAction SilentlyContinue
    
        
}


#####################################################################################################################################

$ScriptPath = "path to your script"
$ScriptName = "$($RecommendationGroupName).ps1"
$IntuneParams = @{
    ScriptName = $ScriptName
    ScriptContent = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((Get-Content -Path "$ScriptPath\$ScriptName" -Raw -Encoding UTF8)))
    DisplayName = "$($RecommendationGroupName)"
    Description = "$($RecommendationGroupName)"
    RunAsAccount = "system" # or user
    EnforceSignatureCheck = "false"
    RunAs32Bit = "false"
}
$IntuneJson = @"
{
    "@odata.type": "#microsoft.graph.deviceManagementScript",
    
    "displayName": "$($IntuneParams.DisplayName)",
    "description": "$($IntuneParams.Description)",
    "scriptContent": "$($IntuneParams.ScriptContent)",
    "runAsAccount": "$($IntuneParams.RunAsAccount)",
    "enforceSignatureCheck": $($IntuneParams.EnforceSignatureCheck),
    "fileName": "$($IntuneParams.ScriptName)",
    "runAs32Bit": $($IntuneParams.RunAs32Bit)
}
"@

$IntuneURI = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts"
#$IntuneURI = "deviceManagement/deviceManagementScripts"
$Response = (Invoke-RestMethod -Method POST -Uri $IntuneURI -Body $IntuneJson -Headers $headers -ContentType "application/json") 


<#
Write-Host "Intune Devices Script created with following Settings:"
Write-Host
Write-Host "$($Response).value."id""
Write-Host "$($Response).value."FileName""

#>





#################################################################################################

$ScriptName = "$($RecommendationGroupName)"
#$IntuneScript = Get-IntunePowerShellScript -ScriptName $ScriptName
$IntuneURIFilter = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts?filter=displayname eq '$($IntuneParams.DisplayName)'"
$IntuneScripts = (Invoke-RestMethod -uri $IntuneURIFilter -Method Get -Headers $headers).value

$IntuneScriptId = $($IntuneScripts.id)

$ScriptJson = @"
{
    "deviceManagementScriptGroupAssignments": [
        {
          "@odata.type": "#microsoft.graph.deviceManagementScriptGroupAssignment",
          "id": "$($IntuneScriptId)",
          "targetGroupId": "$($MemebersGroupId)"
        }
      ]
}
"@
$IntuneScriptURI = "https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts/$($IntuneScriptId)/assign"



Invoke-RestMethod -Method Post -Headers $headers -Uri $IntuneScriptURI -Body $ScriptJson -ContentType "application/json"



##################################################################################################################################  
