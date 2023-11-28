#initialize variables

$makechanges = $true
$bamboousers = ""
$bbhiredate = ""
$bamboouser = ""
$bbworkemail = ""
$bbid = ""
$bblastname = ""
$bbpreferredname = ""
$bbfirstname = ""
$bbhomeemail = ""
$bbdepartment = ""
$bbname = ""
$bbemail = ""
$bbcity = ""
$adusername = ""
$password = ""
$newaduser = ""
$users = ""
$today = ""
$message = ""
$Response = ""
$daysbeforehire = "18"
$response = ""
$secureString = ""
$itapassword = ""
$userlinuxid = ""
$userlinuxuid = ""
$userlinuxgid = ""


'Connecting to Azure AD'
$servicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'         
Connect-AzureAD `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

$attributename = (Get-AzureADApplicationExtensionProperty -ObjectId (Get-AzureADApplication -SearchString "My Properties Bag").ObjectId).Name



#Get list of active users from BambooHR
"Getting BambooHR Users"
$bambooapi = Get-AutomationVariable -Name 'bamboohr_api_key'
$bamboousers = @(Get-BambooHRDirectory -Apikey $bambooapi -subDomain "test" -active -fields "id,preferredName,firstname,lastname,hiredate,jobTitle,city,country,workEmail,homeEmail,status,department")

#Checking for new hires and preparing to add them to AD
"Checking for new hires..."

Foreach ($bamboouser in $bamboousers) {
    
    #Get Today's Date
    $today = Get-Date -format s
    
    $bbhiredate = $bamboouser.hiredate
    $bbworkemail = $bamboouser.workEmail
    
    if (($bbhiredate) -and ($bbhiredate -ge $today)) {
            #get info for the user
            $bbid = $bamboouser.id 
            $bblastname = $bamboouser.lastname
            $bblastname = $bblastname -replace '\s', ''
            $bbpreferredname = $bamboouser.preferredName
            $bbfirstname = $bamboouser.firstname
            $bbhomeemail = $bamboouser.homeemail
            if ($bbpreferredname) {
                $bbfirstname = $bbpreferredname
            }
            $bbfirstname = $bbfirstname -replace '\s', ''
            $bbname = $bbfirstname + " " + $bblastname
            $bbemail = ($bbfirstname + '.' + $bblastname + "@test.com").ToLower() 
            $bbtitle = $bamboouser.jobTitle
            $bbcity = $bamboouser.city
            $bbdepartment = $bamboouser.department

            # Deal with employees with a future hire date that will be missing some fields
            # However, only if hire date is coming within our setup range

            # Used to fetch individul employees 
            $Password = 'x' | ConvertTo-SecureString -AsPlainText -Force
            $Cred = New-Object -typename System.Management.Automation.PSCredential -Argumentlist $bambooapi,$Password
            $Headers = @{'Accept'='application/json'}

        if ($bbhiredate -ne "0000-00-00") {
            
            $bbhiredate = [datetime]$bbhiredate
            $today = [datetime]$today

            if (($bbhiredate -gt $today) -and `
                ($bbhiredate -le $today.AddDays($daysbeforehire))) {
                $URI = "https://api.bamboohr.com/api/gateway.php/test/v1/employees/{0}/?onlyCurrent=False&fields=department" -f $bbid
                try {
                    $Response = Invoke-WebRequest -Method 'GET' -Headers $Headers -Credential $Cred -Uri $URI -UseBasicParsing | ConvertFrom-Json
                    $bbdepartment = $Response.department
                   
                } catch {
                    
                    $message += "Could not get BambooHR user $bbemail, URI: $URI, error: " +  $_.Exception.Message + "</ br>" 
                    
                }
            }
        }
          if (($bbdepartment -eq "101") -or ($bbdepartment -eq "102") -or ($bbdepartment -eq "103") -or ($bbdepartment -eq "104") -or ($bbdepartment -eq "105") ) {
            $adusername = (($bbfirstname.Substring(0, [math]::Min($bbfirstname.Length, 1)))+$bblastname).ToLower() -replace '-',''
            if (Get-ADUser $adusername -ErrorAction Ignore) {
                    continue }
                    elseif (!((Get-AdUser $adusername | select -ExpandProperty displayname) -eq $bbname)) {
                       $adusername = (($bbfirstname.Substring(0, [math]::Min($bbfirstname.Length, 2)))+$bblastname).ToLower() -replace '-',''
                       }
                       
                
                  $users += "User " + $adusername + " does not exist and will be created<br />"

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
                    $password += Get-RandomCharacters -length 1 -characters '!?%@#*'
                    $password = Scramble-String $password
                    $secureString = convertto-securestring "$password" -asplaintext -force

                    $upn = $adusername + "@kan.testsystems.com"

                   
                   if ($makechanges) {

                    "Creating user $bbemail in Local AD"

                    try {
                        New-ADUser -UserPrincipalName $upn -Name $bbname -GivenName $bbfirstname -Surname $bblastname -DisplayName $bbname -SamAccountName $adusername -AccountPassword $securestring -EmailAddress $bbemail -PasswordNeverExpires $true -Enabled $true
                        $newaduser = Get-ADUser $adusername
                        $users += $bbemail + " created in Local AD." + " Username: " + $newaduser.userprincipalname + " Password: $password <br /> Title: $bbtitle <br /> Department: $bbdepartment <br /><br />"
                        }
                    catch {
                        $message += "Could not Create user $bbemail in AD: " + $_.Exception.Message + "<br />"

                        }
                    "Adding AD username to AzureAD"
                    try {
                        Set-AzureADUserExtension -ObjectId $bbemail -ExtensionName $AttributeName -ExtensionValue $adusername
                        }
                    catch {
                        $message += "Could not add $adusername to Azure AD for $bbemail : " + $_.Exception.Message + "<br />"
                        }
                    "Adding user $bbemail to Local AD groups"

                    Add-ADGroupMember -Identity cvsgroup -Members $adusername
                    Add-ADGroupMember -Identity rnd -Members $adusername
                    if ($bbdepartment -eq "107") {
                        Add-ADGroupMember -Identity operations -Members $adusername
                    }

                    
                    "Creating user $bbemail on test1"

                    $itapassword = Get-AutomationVariable -Name 'itautomation_linux'
                    
                    try {
                        C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo useradd $adusername" 
                        }
                    catch {
                        $message += "Could not execute on test1 command for $bbemail : " + $_.Exception.Message + "</ br>"  
                        }
                          
                    try {      
                        C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword " echo '$password' | sudo passwd $adusername --stdin"
                       } 
                    catch {
                        $message += "Could not execute on test1 command for $bbemail : " + $_.Exception.Message + "</ br>"  
                        }
                            
                    #try {    
                    #    C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo usermod -aG cvsgroup $adusername"
                    #    }
                    #catch {
                    #    $message += "Could not execute command on test1 for $bbemail : " + $_.Exception.Message + "</ br>"
                    #    }

                    if ($bbdepartment -eq "101") {
                        try {
                            C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo usermod -g operations $adusername"
                            }
                        catch {
                            $message += "Could not execute command on test1 for $bbemail : " + $_.Exception.Message + "</ br>"
                            }
                        }
                    if (($bbdepartment -eq "102") -or ($bbdepartment -eq "202")) {
                        try {    
                            C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo usermod -g support $adusername"
                            }
                         catch {
                            $message += "Could not execute on test1 command for $bbemail : " + $_.Exception.Message + "</ br>"
                            }   
                        } 
                     if ($bbdepartment -eq "103") {
                        try {    
                            C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo usermod -g it $adusername"
                            }
                         catch {
                            $message += "Could not execute on test1 command for $bbemail : " + $_.Exception.Message + "</ br>"
                            }   
                        }         
                    try {    
                        C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "echo '"$adusername":     $bbemail' | sudo tee -a /etc/aliases >/dev/null"
                       }
                    catch {
                            $message += "Could not execute on test1 command for $bbemail : " + $_.Exception.Message + "</ br>"
                        }

                    try {    
                        C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo newaliases"
                       }
                    catch {
                        $message += "Could not execute command on test1 for $bbemail : " + $_.Exception.Message + "</ br>"
                        }

                    try {        
                        C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo make -C /var/yp"
                       } 
                    catch {
                        $message += "Could not execute command on test1 for $bbemail : " + $_.Exception.Message + "</ br>"
                        }

                     try {       
                        $userlinuxid = C:\"Program Files"\PuTTY\plink.exe -batch -ssh test1 -l itautomation -pw $itapassword "sudo id $adusername"
                        }
                     catch {
                        $message += "Could not execute command on test1 for $bbemail : " + $_.Exception.Message + "</ br>"
                        }   
                    
                    "Setting UID and GID in Local AD for $bbemail"

                    $userlinuxid -match "uid=(?<content>.[^(]*)"
                    $userlinuxuid = ($matches['content']) 
                    $userlinuxid -match "gid=(?<content>.[^(]*)"
                    $userlinuxgid = ($matches['content'])
                    if (($userlinuxuid -ne $null) -and ($userlinuxgid -ne $null)) { 
                        try {
                        Set-ADUser -Identity $adusername -Replace @{uidnumber=$userlinuxuid}
                        Set-ADUser -Identity $adusername -Replace @{gidnumber=$userlinuxgid}
                           }
                        catch {
                            $message += "Could not set UID and GID for $bbemail :" + $_.Exception.Message + "</ br>"
                            }    
                        }
                    else {
                        $message += "Problem setting uid and gid for $aduser."
                        }

                    "Configuring svnpasswd files for $bbemail" 

                    try {
                        C:\"Program Files"\PuTTY\plink.exe -batch -ssh sol-repo -l itautomation -pw $itapassword "echo '$adusername = $password' | sudo tee -a /etc/svnRNDpasswd >/dev/null"
                       }
                    catch {
                        $message += "Could not execute on sol-repo command for $bbemail : " + $_.Exception.Message + "</ br>"  
                        }    
                    if ($bbdepartment -eq "112") {
                        try {    
                            C:\"Program Files"\PuTTY\plink.exe -batch -ssh sol-repo -l itautomation -pw $itapassword "echo '$adusername = $password' | sudo tee -a /etc/svnITpasswd >/dev/null"
                           }
                        catch {
                            $message += "Could not execute on sol-repo command for $bbemail : " + $_.Exception.Message + "</ br>"  
                            }    
                        }
                    if ($bbdepartment -eq "113") {
                        try {    
                            C:\"Program Files"\PuTTY\plink.exe -batch -ssh sol-repo -l itautomation -pw $itapassword "echo '$adusername = $password' | sudo tee -a /etc/svnOPSpasswd >/dev/null"
                           }
                        catch {
                            $message += "Could not execute on sol-repo command for $bbemail : " + $_.Exception.Message + "</ br>"  
                            }    
                        }
                    if (($bbdepartment -eq "104") -or ($bbdepartment -eq "106")) {
                        try {
                            C:\"Program Files"\PuTTY\plink.exe -batch -ssh sol-repo -l itautomation -pw $itapassword "echo '$adusername = $password' | sudo tee -a /etc/svnOPSpasswd >/dev/null"
                           }
                        catch {
                            $message += "Could not execute on sol-repo command for $bbemail : " + $_.Exception.Message + "</ br>"  
                            }
                    if (($bbtitle -match "\sQA\s") -or ($bbdepartment -eq "605)) {
                        try {
                            C:\"Program Files"\PuTTY\plink.exe -batch -ssh sol-repo -l itautomation -pw $itapassword "echo '$adusername = $password' | sudo tee -a /etc/svnQApasswd >/dev/null"
                           }
                        catch {
                            $message += "Could not execute on sol-repo command for $bbemail : " + $_.Exception.Message + "</ br>"  
                            }            
                        }

                    }
                    

                }
            }
        }
}

if ($makechanges) {
            
    $MyCredential = "it-automation"
    $Cred = Get-AutomationPSCredential -Name $MyCredential
    if ($Cred -eq $null) 
    { 
        Write-Output "Credential entered: $MyCredential does not exist in the automation service. Please create one `n"    
    } 
          if ($users -ne '') {  
            $body = "The following users have been added to Local AD and Linux. Please provide their credentials in their welcome emails.<br /><br />" + $users `
                     + "<br /><br />" + "Errors:<br /><br />" + $message   
            Send-MailMessage -To 'it-internal@test.com' -Subject 'Local AD New Users' -BodyAsHtml -Body $body -UseSsl -Port 587 -SmtpServer 'smtp.office365.com' -From 'it-automation@test.com' -Credential $Cred 
            }
        }

$users + "`n"

$message

Disconnect-AzureAD