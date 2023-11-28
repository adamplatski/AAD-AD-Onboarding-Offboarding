$global:MakeChanges = $false #If false, the script will report what it would do but will not make any changes.

#Get Today's Date
$today = Get-Date -format s

Write-Output "Today's date is $today"

#Connect to AzureAD
$connectionName = "AzureRunAsConnection"
    
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

"Logging in to Azure..."
Connect-AzureAD `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

#connect to MSOnline
$MSPassword = Get-AutomationVariable -Name 'itautomation_secret' | ConvertTo-SecureString -AsPlainText -Force
$msolCred = New-Object -typename System.Management.Automation.PSCredential -Argumentlist 'it-automation@test.com', $MSPassword 

"Connecting to Exchange Online" 
Connect-MsolService -Credential $msolCred

#initialize variables
$license = ""
$EOlicense = ""
$EPlicense = ""
$EMSlicense = ""
$AClicense = ""
$licensestatus = ""
$userstatus = ""
$firstname = ""
$lastname = ""
$Displayname = ""
$email = ""
$bbemail = ""
$jobtitle = ""
$city = ""
$bbcity = ""
$usercountry = ""
$PasswordProfile = ""
$users = ""
$sso_user = ""
$bbterminationdate = ""
$MSPassword = ""
$prestartObjectId = ""
$userObjectId = ""
$adjdate = ""
$bbhiredate_convert = ""
$bamboousers = ""
$checkBamboohrEmail = ""
$global:UserExclusions = 'jonny@test.com','timmy@test.com'


# Create the objects we'll need to add and remove AAD licenses
$EOlicense = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$EPlicense = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$EMSlicense = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$AClicense = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$license = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses

# Find the SkuID of the license we want to add - in this case, Exchange Online (Plan 1)
$EOlicense.SkuId = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "EXCHANGESTANDARD" -EQ).SkuId

# Find the SkuID of the license we want to add - in this case, ENTERPRISE MOBILITY + SECURITY E3
$EMSlicense.SkuId = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "EMS" -EQ).SkuId

# Find the SkuID of the license we want to add - in this case, Office 365 E3
$EPlicense.SkuId = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "ENTERPRISEPACK" -EQ).SkuId

# Find the SkuID of the license we want to add - in this case, Microsoft 365 Audio Conferencing
$AClicense.SkuId = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "MCOMEETADV" -EQ).SkuId

                                
#Check for the amount of licenses
$EOused = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "EXCHANGESTANDARD" -EQ).ConsumedUnits
$EOtotal = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "EXCHANGESTANDARD" -EQ).PrepaidUnits.Enabled

$EPused = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "ENTERPRISEPACK" -EQ).ConsumedUnits
$EPtotal = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "ENTERPRISEPACK" -EQ).PrepaidUnits.Enabled

$EMSused = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "EMS" -EQ).ConsumedUnits
$EMStotal = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "EMS" -EQ).PrepaidUnits.Enabled

$ACused = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "MCOMEETADV" -EQ).ConsumedUnits
$ACtotal = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value "MCOMEETADV" -EQ).PrepaidUnits.Enabled
                

#Country codes

$countrycodes = @(
    [PSCustomObject]@{
        country = "Australia"
        code    = "AU"
    },
    [PSCustomObject]@{
        country = "Canada"
        code    = "CA"
    },
    [PSCustomObject]@{
        country = "China"
        code    = "CN"
    },
    [PSCustomObject]@{
        country = "France"
        code    = "FR"
    },
    [PSCustomObject]@{
        country = "Germany"
        code    = "DE"
    },
    [PSCustomObject]@{
        country = "Hong Kong"
        code    = "HK"
    },
    [PSCustomObject]@{
        country = "India"
        code    = "IN"
    },
    [PSCustomObject]@{
        country = "Korea (South)"
        code    = "KR"
    },
    [PSCustomObject]@{
        country = "Singapore"
        code    = "SG"
    },
    [PSCustomObject]@{
        country = "Sweden"
        code    = "SE"
    },
    [PSCustomObject]@{
        country = "Switzerland"
        code    = "CH"
    },
    [PSCustomObject]@{
        country = "United Kingdom"
        code    = "GB"
    },
    [PSCustomObject]@{
        country = "United States"
        code    = "US"
    }
)

#Get list of active users from BambooHR
"Getting BambooHR Users"
$bambooapi = Get-AutomationVariable -Name 'bamboohr_api_key'
$bamboousers = @(Get-BambooHRDirectory -Apikey $bambooapi -subDomain "test" -active -fields "id,preferredName,firstname,lastname,hiredate,employmentHistoryStatus,terminationdate,jobTitle,city,country,workEmail,homeEmail")

#Checking for new hires and preparing to add them to AzureAD
"Checking for new hires..."

Foreach ($bamboouser in $bamboousers) {
    $bbhiredate = $bamboouser | select -ExpandProperty hiredate
    $bbworkemail = $bamboouser | select -ExpandProperty workEmail
    #$bbemail = $bbfirstname + '.' + $bblastname + "@test.com" 
    
    if ($bbhiredate -ge $today) {
        
            #get info for the user
            $bbid = $bamboouser | select -ExpandProperty id 
            $bblastname = $bamboouser | select -ExpandProperty lastname
            $bblastname = $bblastname -replace '\s', ''
            $bbpreferredname = $bamboouser | select -ExpandProperty preferredName
            $bbfirstname = $bamboouser | select -ExpandProperty firstname
            $bbhomeemail = $bamboouser | select -ExpandProperty homeEmail
            if ($bbpreferredname) {
                $bbfirstname = $bbpreferredname
            }
            $bbfirstname = $bbfirstname -replace '\s', ''
            $bblastname = $bblastname -replace "'",''
            $bbname = $bbfirstname + " " + $bblastname
            $bbemail = $bbfirstname + '.' + $bblastname + "@test.com" 
            $bbtitle = $bamboouser | select -ExpandProperty jobTitle
            $bbcity = $bamboouser | select -ExpandProperty city
            $bbterminationdate = $bamboouser | select -ExpandProperty terminationdate
            $bbemploymentstatus = $bamboouser | select -ExpandProperty employmenthistorystatus


            $checkUserExists = $null
            $checkUserExists = Get-AzureADUser -ObjectID $bbemail -ErrorAction SilentlyContinue
            if ($checkUserExists -eq $null) {
                    if ($bbworkemail -ne $null) {
                    $users += "$bbfirstname $bblastname has updated their information:<br />Name: $bbname<br />Email: $bbemail<br /> Please update in all relevant systems. <br />"
                    $users += "***Inform users of any changes!***<br /><br />"
                } else {    
                    $users += "$bbemail does not exist in AzureAD and will be created...<br />" 

                    $users += "Name: $bbname <br /> Title: $bbtitle <br /> Start date: $bbhiredate <br /> Email: $bbemail<br />"

                    #Now we'll proceed to create the user

                    #random password generation
                    function Get-RandomCharacters($length, $characters) {
                        $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length }
                        $private:ofs = ""
                        return [String]$characters[$random]
                    }

                    function Scramble-String([string]$inputString) {
                        $characterArray = $inputString.ToCharArray()
                        $scrambledStringArray = $characterArray | Get-Random -Count $characterArray.Length
                        $outputString = -join $scrambledStringArray
                        return $outputString
                    }

                    $password = Get-RandomCharacters -length 3 -characters 'abcdefghiklmnoprstuvwxyz'
                    $password += Get-RandomCharacters -length 2 -characters 'ABCDEFGHKLMNOPRSTUVWXYZ'
                    $password += Get-RandomCharacters -length 2 -characters '1234567890'
                    $password += Get-RandomCharacters -length 1 -characters '!?%&@#*'
                    $password = Scramble-String $password
                    
                    #Get country code
                    Foreach ($countrycode in $countrycodes) {
                        $country
                        if ($countrycode.country -eq $usercountry) {
                            $bbcountrycode = $countrycode.code
                        }
                        if (!$bbcountrycode) {
                            $bbcountrycode = "CA"
                        }
                    }
                    $countrycode = $bbcountrycode

                    $users += "The country code selected was $countrycode. Please verify this is correct. <br /><br />"

                    #Set info for the user
                    $firstname = $bbfirstname
                    $lastname = $bblastname
                    $Displayname = $firstname + " " + $lastname
                    $email = $bbemail
                    $jobtitle = $bbtitle
                    $location = $bblocation
                    $usercountry = $bamboouser | select -ExpandProperty country
                    $PasswordProfile = New-Object -TypeName Microsoft.Open.AzureAD.Model.PasswordProfile
                    $PasswordProfile.Password = $password

                    #Create the user
                    $userparams = @{ 'DisplayName' = $Displayname;
                        'PasswordProfile'          = $PasswordProfile;
                        'UserPrincipalName'        = $email;
                        'AccountEnabled'           = $true; 
                        'GivenName'                = $firstname;
                        'Surname'                  = $lastname;
                        'mailnickname'             = $firstname + $lastname;
                        'Country'                  = $usercountry;
                        'UsageLocation'            = $countrycode 
                    }
                    if ($global:MakeChanges -eq $true) {
                        New-AzureADUser @userparams -ErrorAction SilentlyContinue
                    }

                    If (Get-Azureaduser -ObjectId $email -ErrorAction SilentlyContinue) {
                        $users += "User $email was successfuly created. The password is: $password <br />"
                    }
             
                    # Set the Exchange Online license as the license we want to add in the $licenses object
                    If ($EOused -lt $EOtotal) {
                        $AssignedLicenses = (Get-AzureADUser -ObjectId $email).AssignedLicenses
                        if ($AssignedLicenses.Count -eq 0) {
                            if ($global:MakeChanges -eq $true) {
                                $license.AddLicenses = $EOlicense
                                Set-AzureADUserLicense -ObjectId $email -AssignedLicenses $license
                                "Assigned Exchange Online License to $bbemail"
                                $users += "License assigned: Exchange Online (Plan 1) - Recipient: $bbemail (Please verify in the O365 Admin Portal) <br />"
                            }
                        }
                    } 
                    elseif ($EOused -gt $EOtotal) {
                        $users += "License assigned: none (Please purchase and assign a license in the O365 Admin Portal) <br />"
                        "Not enough licenses; did not assign Exchange Online license to $bbemail"
                    }
                  
                    #Now we will assign the BambooHR app to the user

                    # Assign the values to the variables
                    $app_name = "testBambooHR"
                    $app_role_name = "msiam_access"

                    # Get the user to assign, the service principal and role for the app to assign to
                    $sso_user = Get-AzureADUser -ObjectID "$email"
                    $sp = Get-AzureADServicePrincipal -Filter "displayName eq '$app_name'"
                    $appRole = $sp.AppRoles | Where-Object { $_.DisplayName -eq $app_role_name }

                    # Assign the user to the app role
                    if ($global:MakeChanges -eq $true) {
                        New-AzureADUserAppRoleAssignment -ObjectId $sso_user.ObjectId -PrincipalId $sso_user.ObjectId -ResourceId $sp.ObjectId -ID $appRole.Id 
                    }
                    "Added BambooHR app role to $bbemail"
                    if (Get-AzureADUserAppRoleAssignment -ObjectId $sso_user.ObjectId -ErrorAction SilentlyContinue) {
                        $users += "User added to BambooHR SSO role. <br /><br />" 

                        #Add work email to BambooHR profile
                        if ($global:MakeChanges -eq $true) {
                            Update-BambooHRUser -Apikey $bambooapi -subDomain "test" -id $bbid -fields @{workEmail = $bbemail }
                            $checkBamboohrEmail = Get-BambooHRUser -Apikey $bambooapi -subDomain "test" -id $bbid -fields "id,workEmail"
                            if ($checkBamboohrEmail.workemail -ne $null) {
                                $users += "Updated email in BambooHR profile for $bbemail"
                                $bbworkemail = $bamboouser | select -ExpandProperty workEmail
                            }
                            else {
                                $users += "Updating email in BambooHR profile unsuccessful. Retrying. Please verify manually."
                                Update-BambooHRUser -Apikey $bambooapi -subDomain "test" -id $bbid -fields @{workEmail = $bbemail }
                            }
                        }
                        else {
                            $users += "BambooHR assignment unsuccessful. <br /><br />" 
                        }
                        else {
                            $users += "User $bbemail creation failed. <br /><br />"
                        }
                 
                        #send email to user

                        if ($global:MakeChanges -eq $true) {
                            #first check if the prerequisites are in place - license, BambooHR app assignment, work email in BambooHR

                            $statuserror = 0
                            $AssignedLicenses = ""

                            $AssignedLicenses = (Get-AzureADUser -ObjectId $bbemail).AssignedLicenses
                            If ($AssignedLicenses.Count -eq 0) {
                                $statuserror = 1
                                $users += "Cannot proceed due to missing license. Please assign a license in the Office365 Admin Portal before emailing the user their credentials. <br /><br />"
                            }

                            If (!(Get-AzureADUserAppRoleAssignment -ObjectId $sso_user.ObjectId -ErrorAction SilentlyContinue)) {
                                $statuserror = 1
                                $users += "Cannot proceed due to missing BambooHR Assignment. Please assign the BambooHR application in the Azure AD Portal before emailing the user their credentials. <br /><br />"
                            }

                            If ($bbworkemail = "") {
                                $statuserror = 1
                                $users += "Cannot proceed because the user's test email is not in BambooHR. Please add it to the work email section of their profile before emailing the user their credentials. <br /><br />"
                            }
                        }


                        $MyCredential = "it-automation" 
                        $Body = "Hi $firstname,<br /><br /> ` 
            Welcome to the team! <br /><br /> `
            We have started your onboarding process. `
            This includes access to test resources, your accounts, and your equipment. A member of the IT team will contact you soon with further details. <br /><br />
            Thanks" 
                        $subject = "Welcome to test, $firstname! - BambooHR Login Info"  

                        # Get the PowerShell credential and prints its properties 
                        $Cred = Get-AutomationPSCredential -Name $MyCredential
                        if ($Cred -eq $null) { 
                            Write-Output "Credential entered: $MyCredential does not exist in the automation service. Please create one `n"    
                        } 
                        else { 
                            $CredUsername = $Cred.UserName 
                            $CredPassword = $Cred.GetNetworkCredential().Password 
                        } 
    
                        If ($statuserror -ne "1") {
                            "Sending email to user $bbemail"
                            $users += "End user creation. <br /> <br />"  
                            if ($global:MakeChanges -eq $true) {
                                Send-MailMessage -To $bbhomeemail -Bcc 'it-internal@test.com' -Cc 'timmy@test.com -Subject $subject -Body $Body -UseSsl -Port 587 -SmtpServer 'smtp.office365.com' -From 'test IT <it-automation@test.com>' -BodyAsHtml -Credential $Cred
                            }

                            #For Testing Only
                            #Send-MailMessage -To 'jonny@test.ca' -Subject $subject -Body $Body -UseSsl -Port 587 -SmtpServer 'smtp.office365.com' -From 'test IT <it-automation@test.com>' -BodyAsHtml -Credential $Cred
                        }
                    }
                }
            } 
            #Get the date 48 hours before the hire date and convert it back to a string
            $bbhiredate_convert = [datetime]::ParseExact($bbhiredate, 'yyyy-MM-dd', $null)
            $adjdate = $bbhiredate_convert.AddHours(-48)
            $adjdate = $adjdate.ToString('yyyy-MM-dd')
            
            #setup the pre-start group
            $userObjectId = (Get-AzureADUser -ObjectId $bbemail).ObjectId
            $prestartObjectId = (Get-AzureADGroup -SearchString "pre-start").ObjectId
            $prestartmembership = (Get-AzureADGroupMember -ObjectId $prestartObjectId -All $true | Where-Object { $_.ObjectId -eq $userObjectid })


            #Add users to a group for conditional access, limiting them to email and BambooHR only until 48 hours before their start date
            if ($today -le $adjdate) {   
                if ($prestartmembership -eq $null) {
                    if ($global:UserExclusions -notcontains $bbemail) {
                        if ($global:MakeChanges -eq $true) {
                            Add-AzureADGroupMember -ObjectID $prestartObjectId -RefObjectId $userObjectId
                            "Added $bbemail to the pre-start group."
                        }
                    }
                }
            }  

            #Remove users from pre-start group and their EO license 48 hours before their start date
            if ($today -ge $adjdate) {
                if ($prestartmembership -ne $null) {
                    if ($global:MakeChanges -eq $true) {
                        Remove-AzureADGroupMember -ObjectID $prestartObjectId -memberId $userObjectId
                        $license.RemoveLicenses = "4b9405b0-7788-4568-add1-99614e613b69"
                        "Removed $bbemail from the AAD Pre-Start Group"
                        "Removed the Exchange Online license from $bbemail's AAD account"
                    }
                }
            }
            
            #Assign the three standard licenses to all new employees 48 hours before their start date
            if ($today -ge $adjdate) {
                If ($EPused -lt $EPtotal) {
                    if ($EMSused -lt $EMStotal) {
                        if ($ACused -lt $ACtotal) {
                            if ($global:MakeChanges -eq $true) {
                                $license.AddLicenses = $EMSlicense, $EPlicense, $AClicense
                                Set-AzureADUserLicense -ObjectId $bbemail -AssignedLicenses $license
                                "Assigned three licenses to $bbemail : Microsoft Audio Conferencing, Office365 E3, Enterprise Mobility + Security E3"
                            }
                        }
                    }
                }
            }
                
    }
}

#send email

if ($users) {
    "New Users exist or user(s) have changed their information. Sending email to IT."
    $MyCredential = "it-automation" 
    $Body = "Below is a list of new hires in BambooHR which have now been added to AzureAD. Please confirm they have been assigned an appropriate license. <br /><br />$users" 
    $subject = "New AzureAD Users"  
      
    # Get the PowerShell credential and prints its properties 
    $Cred = Get-AutomationPSCredential -Name $MyCredential
    if ($Cred -eq $null) { 
        Write-Output "Credential entered: $MyCredential does not exist in the automation service. Please create one `n"    
    } 
    else { 
        $CredUsername = $Cred.UserName 
        $CredPassword = $Cred.GetNetworkCredential().Password 
    } 
         
    if ($global:MakeChanges -eq $true) {
        Send-MailMessage -To 'it-internal@test.com' -Subject $subject -Body $Body -UseSsl -Port 587 -SmtpServer 'smtp.office365.com' -From 'it-automation@test.com' -BodyAsHtml -Credential $Cred
    }
}

"Disconnecting from AzureAD"
Disconnect-AzureAD