$global:MakeChanges = $True
$global:Errors = ''
$global:Changes = ''
function AddToErrors([string] $NewString) {
    $global:Errors += "$NewString`n"
}

'Connecting to Azure AD'
$servicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'        
$ConnectAzure = Connect-AzureAD `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

$Password = Get-AutomationVariable -Name 'itautomation_secret' | ConvertTo-SecureString -AsPlainText -Force
$msolCred = New-Object -typename System.Management.Automation.PSCredential -Argumentlist 'test@test.com', $Password
Connect-MsolService -Credential $msolCred

"Getting Azure AD users"
$AadUsers = Get-AzureAdUser -All $True -Filter "usertype eq 'Member'"

"Indexing Azure AD users"
$AzureUsers = @{}
$Index = 0
foreach ($User in $AadUsers) {
    if ($User.Mail) {
        $AzureUsers[$User.Mail] = $Index
    }
    $Index++
}

'Getting BambooHR users'
$BambooUsersById = @{}
$BambooApiKey = Get-AutomationVariable -Name 'bamboohr_api_key'
$BambooDirectory = @(Get-BambooHRDirectory -Apikey $BambooApiKey -subDomain "" -active `
        -fields "employeeNumber,jobTitle,location,country,workEmail,mobilePhone,workPhonePlusExtension,workPhone,workPhoneExtension,hiredate,employmentHistoryStatus,supervisorEId")

"Indexing BambooHR users"
$BambooUsersById = @{}
$Index = 0
foreach ($BambooUser in $BambooDirectory) {
    $BambooUsersById[$BambooUser.id] = $Index
    $Index++
}

#Country codes
$countrycodes = @{
    "Australia"      = "AU"
    "Canada"         = "CA"
    "China"          = "CN"
    "France"         = "FR"
    "Germany"        = "DE"
    "Hong Kong"      = "HK"
    "India"          = "IN"
    "Korea (South)"  = "KR"
    "Singapore"      = "SG"
    "Sweden"         = "SE"
    "Switzerland"    = "CH"
    "United Kingdom" = "GB"
    "United States"  = "US"
}

"Checking countries for each BambooHR user"
foreach ($BambooUser in $BambooDirectory) {
    $needchange = $False
    $Email = $BambooUser.workEmail
    if ($Email) {
        if ($AzureUsers.ContainsKey($Email)) {
            $AdUser = $AadUsers[$AzureUsers[$Email]]
            if ($BambooUser.country -ne $AdUser.Country) {
                $global:Changes += "Need to set country for $Email`n"
                "Need to set country for $Email"
                $needchange = $True
            }

            $bbcountrycode = $countrycodes[$BambooUser.country]
            if ($bbcountrycode) {
                if ($AzureUsers.ContainsKey($bbcountrycode)) {
                    $AdUser = $AadUsers[$AzureUsers[$bbcountrycode]]
                    if ($AdUser.UsageLocation -ne $AdUser.$bbcountrycode) {
                        $global:Changes += "Need to set country code for $Email`n"
                        $needchange = $True
                    }
                }
                if($null -eq $bbcountrycode){
                    AddToErrors("Country code missing for '" + $BambooUser.country + "'")
                }
                
                $ManagerId = $BambooUser.supervisorEId
                if ($ManagerId -and $BambooUsersById.ContainsKey($ManagerId)) {
                    $ManagerEmail = $BambooDirectory[$BambooUsersById[$ManagerId]].workEmail
                    if ($AzureUsers.ContainsKey($ManagerEmail)) {
                        $ManagerObjectId = $AAdUsers[$AzureUsers[$ManagerEmail]].ObjectId
                        $CurrentManagerObjectId = Get-AzureADUserManager -ObjectId $AdUser.objectId | Select-Object -ExpandProperty ObjectId
                        if ($ManagerObjectId -ne $CurrentManagerObjectId) {
                            $global:Changes += "Need to set manager for $Email`n"
                            "Setting Manager for $Email"	
                            if ($global:MakeChanges) {
                                Set-AzureADUserManager -ObjectId $AdUser.ObjectId -RefObjectId $ManagerObjectId
                            }
                        }
                    }
                    
                    else {
                        "$Email has no manager. Removing."
                        if ($global:MakeChanges) {	
                            Remove-AzureADUserManager -ObjectId $AdUser.ObjectId
                        }
                    }
                }
                else {
                    "$Email not found in Azure AD"
                }
            }
        
    

            #Populate variables with details from BambooHR

            $AzureADUser = $AadUsers[$AzureUsers[$Email]]

            if ($AzureADuser.PhysicalDeliveryOfficeName -ne $bamboouser.location) {
                $needChange = $true
                $global:Changes += "Need to update location (city) for $Email`n"
                $bamboouser.workemail + " needs location updated in azure from '" + $AzureADuser.PhysicalDeliveryOfficeName + "' to '" + $bamboouser.location + "'"
            }
            if ($AzureADuser.JobTitle -ne $bamboouser.jobTitle) {
                $needChange = $true
                $global:Changes += "Need to update job title for $email`n"
                $bamboouser.workemail + " needs job title updated in azure from '" + $AzureADuser.JobTitle + " ' to '" + $bamboouser.jobTitle + "'"
            }
            if (($null -ne $bamboouser.workPhonePlusExtension) -and ($bamboouser.workPhonePlusExtension -ne '')) {
                if ($AzureADuser.TelephoneNumber -ne $bamboouser.workPhonePlusExtension) {
                    $needChange = $true   
                    $global:Changes += "Need to update phone plus extension for $Email`n"                           
                    $bamboouser.workemail + " needs phone plus extension updated in azure from '" + $AzureADuser.TelephoneNumber + " ' to '" + $bamboouser.workPhonePlusExtension + "'"
                }
            }
            if (($null -ne $bamboouser.mobilePhone) -and ($bamboouser.mobilePhone -ne '')) {
                if ($AzureADuser.Mobile -ne $bamboouser.mobilePhone) {
                    if (!"$AzureADuser.Mobile".Contains("$bamboouser.mobilePhone")) {
                        $needChange = $true
                        $global:Changes += "Need to update mobile for $Email`n"
                        $bamboouser.workemail + " needs mobile updated in azure from '" + $AzureADuser.Mobile + " ' to '" + $bamboouser.mobilePhone + "'"
                    }
                }
            }
        
        
            if ($needChange) {
                $userparams = @{ 
                    'ObjectID'                   = $bamboouser.workemail;
                    'PhysicalDeliveryOfficename' = $bamboouser.location;
                    'Country'                    = $bamboouser.country;
                    'UsageLocation'              = $bbcountrycode;
                    'jobTitle'                   = $bamboouser.jobTitle
                    'TelephoneNumber'            = $bamboouser.workPhonePlusExtension
                    'Mobile'                     = $bamboouser.mobilePhone
                }

                if ($global:MakeChanges) {
                    Set-AzureADUser @userparams -ErrorAction SilentlyContinue -ErrorVariable ChangeError
                    if ($ChangeError) {
                
                        AddToErrors("ERROR: Cannot make changes to $Email")
                    }
                }
            }
        }
    }
}
        
#Send email if any errors
if ($global:Errors) {
    "Sending error email since errors detected"
    $Body = "User info has been updated in AzureAD, by referencing BambooHR. Below is a list of errors.<br /><br />$global:Errors" 
    $subject = "AzureAD User Info Update: Errors"
if ($global:MakeChanges) {
    $MyCredential = "it-automation"
    $Cred = Get-AutomationPSCredential -Name $MyCredential
    Send-MailMessage -To 'test@test.com' -Subject $subject -Body $Body -UseSsl -Port 587 -SmtpServer 'smtp.office365.com' -From 'test@test.com' -BodyAsHtml -Credential $Cred
}
else{
    $Body
    }
}


"Changes to make:"
$global:Changes + "`n"
"Errors:"
$global:Errors

Disconnect-AzureAD